#!/bin/bash

if [[ "$@" == "bash" ]]; then
    exec $@
fi

if [[ -z $RUNNER_NAME ]]; then
    echo "RUNNER_NAME environment variable is not set, using '${HOSTNAME}'."
    export RUNNER_NAME=${HOSTNAME}
fi

if [[ -z $RUNNER_WORK_DIRECTORY ]]; then
    echo "RUNNER_WORK_DIRECTORY environment variable is not set, using '_work'."
    export RUNNER_WORK_DIRECTORY="_work"
fi

# For org-level runners, we need GitHub App credentials
if [[ -z $GITHUB_APP_CLIENT_ID ]]; then
    echo "Error: GITHUB_APP_CLIENT_ID environment variable is not set."
    exit 1
fi

if [[ -z $GITHUB_APP_PEM ]]; then
    echo "Error: GITHUB_APP_PEM environment variable is not set."
    exit 1
fi

if [[ -z $GITHUB_APP_INSTALLATION_ID ]]; then
    echo "Error: GITHUB_APP_INSTALLATION_ID environment variable is not set."
    exit 1
fi

if [[ -z $RUNNER_ORGANIZATION_URL ]]; then
    echo "Error: RUNNER_ORGANIZATION_URL environment variable is required for org-level runners."
    exit 1
fi

if [[ -z $RUNNER_REPLACE_EXISTING ]]; then
    export RUNNER_REPLACE_EXISTING="true"
fi

CONFIG_OPTS=""
if [ "$(echo $RUNNER_REPLACE_EXISTING | tr '[:upper:]' '[:lower:]')" == "true" ]; then
	CONFIG_OPTS="--replace"
fi

if [[ -n $RUNNER_LABELS ]]; then
    CONFIG_OPTS="${CONFIG_OPTS} --labels ${RUNNER_LABELS}"
fi

# Function to generate JWT
generate_jwt() {
    local client_id=$1
    local pem=$2
    
    local now=$(date +%s)
    local iat=$((${now} - 60)) # Issues 60 seconds in the past
    local exp=$((${now} + 600)) # Expires 10 minutes in the future
    
    b64enc() { openssl base64 | tr -d '=' | tr '/+' '_-' | tr -d '\n'; }
    
    local header_json='{
        "typ":"JWT",
        "alg":"RS256"
    }'
    local header=$( echo -n "${header_json}" | b64enc )
    
    local payload_json="{
        \"iat\":${iat},
        \"exp\":${exp},
        \"iss\":\"${client_id}\"
    }"
    local payload=$( echo -n "${payload_json}" | b64enc )
    
    # Signature
    local header_payload="${header}"."${payload}"
    local signature=$(
        openssl dgst -sha256 -sign <(echo -n "${pem}") \
        <(echo -n "${header_payload}") | b64enc
    )
    
    # Create JWT
    local jwt="${header_payload}"."${signature}"
    echo "${jwt}"
}

if [[ -f ".runner" ]]; then
    echo "Runner already configured. Skipping config."
else
    echo "Generating JWT from GitHub App credentials..."
    JWT=$(generate_jwt "${GITHUB_APP_CLIENT_ID}" "${GITHUB_APP_PEM}")
    
    if [[ -z $JWT ]]; then
        echo "Error: Failed to generate JWT"
        exit 1
    fi
    
    echo "Exchanging JWT for GitHub App Installation Access Token..."
    GITHUB_ACCESS_TOKEN=$(curl -X POST \
        -H "Authorization: Bearer ${JWT}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/app/installations/${GITHUB_APP_INSTALLATION_ID}/access_tokens" \
        | jq -r '.token')
    
    if [[ -z $GITHUB_ACCESS_TOKEN || $GITHUB_ACCESS_TOKEN == "null" ]]; then
        echo "Error: Failed to get GitHub App Installation Access Token"
        exit 1
    fi
    
    echo "Exchanging GitHub Access Token for Runner Registration Token..."
    
    _PROTO="$(echo "${RUNNER_ORGANIZATION_URL}" | grep :// | sed -e's,^\(.*://\).*,\1,g')"
    _URL="$(echo "${RUNNER_ORGANIZATION_URL/${_PROTO}/}")"
    _PATH="$(echo "${_URL}" | grep / | cut -d/ -f2-)"
    
    RUNNER_TOKEN="$(curl -XPOST -fsSL \
        -H "Authorization: token ${GITHUB_ACCESS_TOKEN}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/orgs/${_PATH}/actions/runners/registration-token" \
        | jq -r '.token')"
    
    if [[ -z $RUNNER_TOKEN || $RUNNER_TOKEN == "null" ]]; then
        echo "Error: Failed to get Runner Registration Token"
        exit 1
    fi

    echo "Configuring GitHub Actions Runner for organization..."
    ./config.sh \
        --url $RUNNER_ORGANIZATION_URL \
        --token $RUNNER_TOKEN \
        --name $RUNNER_NAME \
        --work $RUNNER_WORK_DIRECTORY \
        --labels your-runner-label \
        $CONFIG_OPTS \
        --unattended
fi

exec "$@"



