FROM gcr.io/kaniko-project/executor as kaniko

FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive
ARG GH_RUNNER_VERSION
ARG DOCKER_COMPOSE_VERSION="v2.24.0"
ARG SONAR_SCANNER_VERSION="5.0.1.3006"

ENV RUNNER_NAME=""
ENV RUNNER_WORK_DIRECTORY="_work"
ENV RUNNER_TOKEN=""
ENV RUNNER_REPOSITORY_URL=""
ENV RUNNER_ORGANIZATION_URL=""
ENV RUNNER_LABELS=""
ENV RUNNER_ALLOW_RUNASROOT=true
ENV GITHUB_ACCESS_TOKEN=""
ENV GITHUB_APP_CLIENT_ID=""
ENV GITHUB_APP_PEM=""
ENV GITHUB_APP_INSTALLATION_ID=""
ENV AGENT_TOOLSDIRECTORY=/opt/hostedtoolcache

# Labels
LABEL maintainer="me@tcardonne.fr" \
    org.label-schema.schema-version="1.0" \
    org.label-schema.name="github-runner" \
    org.label-schema.description="Dockerized GitHub Actions runner."

# Install base packages and add repositories in one layer
RUN apt-get update && apt-get install -y \
    gnupg \
    software-properties-common \
    curl \
    lsb-release \
    wget \
    ca-certificates \
    apt-transport-https \
    && rm -rf /var/lib/apt/lists/*

# Add HashiCorp repository
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list > /dev/null

# Add GitHub CLI repository
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null

# Add Google Chrome repository
RUN curl -fsSL https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/google-chrome-keyring.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome-keyring.gpg] https://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list

# Add PostgreSQL repository
RUN curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/postgresql-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/postgresql-keyring.gpg] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list

# Install all packages in one layer
RUN apt-get update && apt-get install -y \
    unzip \
    sudo \
    supervisor \
    jq \
    iputils-ping \
    build-essential \
    zlib1g-dev \
    gettext \
    liblttng-ust1 \
    libcurl4-openssl-dev \
    terraform \
    coreutils \
    awscli \
    openssh-client \
    gh \
    openjdk-17-jdk \
    ca-certificates-java \
    google-chrome-stable \
    postgresql-client \
    git \
    fontconfig \
    fonts-ipafont-gothic \
    fonts-wqy-zenhei \
    fonts-thai-tlwg \
    fonts-kacst \
    fonts-symbola \
    fonts-noto \
    fonts-freefont-ttf \
    --no-install-recommends \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Set correct JAVA_HOME for Java 17
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64/
RUN update-ca-certificates -f

# Copy supervisor config
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
RUN chmod 644 /etc/supervisor/conf.d/supervisord.conf

# Install Docker CLI
RUN curl -fsSL https://get.docker.com -o- | sh && \
    rm -rf /var/lib/apt/lists/*

# Install Docker Compose v2
RUN curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose && \
    chmod +x /usr/local/bin/docker-compose

# Create directories
RUN mkdir -p /home/runner ${AGENT_TOOLSDIRECTORY}

WORKDIR /home/runner

# Install GitHub Actions Runner
RUN GH_RUNNER_VERSION=${GH_RUNNER_VERSION:-$(curl --silent "https://api.github.com/repos/actions/runner/releases/latest" | grep tag_name | sed -E 's/.*"v([^"]+)".*/\1/')} && \
    curl -L -O "https://github.com/actions/runner/releases/download/v${GH_RUNNER_VERSION}/actions-runner-linux-x64-${GH_RUNNER_VERSION}.tar.gz" && \
    tar -zxf "actions-runner-linux-x64-${GH_RUNNER_VERSION}.tar.gz" && \
    rm -f "actions-runner-linux-x64-${GH_RUNNER_VERSION}.tar.gz" && \
    ./bin/installdependencies.sh && \
    chown -R root: /home/runner && \
    rm -rf /var/lib/apt/lists/*

# Copy Kaniko
COPY --from=kaniko /kaniko /kaniko
ENV HOME=/root
ENV USER=/root
ENV PATH=$PATH:/kaniko
ENV DOCKER_CONFIG=/kaniko/.docker/

# Install SonarScanner
RUN curl -s -L "https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux.zip" -o sonarscanner.zip && \
    unzip -qq sonarscanner.zip && \
    rm -rf sonarscanner.zip && \
    mv "sonar-scanner-${SONAR_SCANNER_VERSION}-linux" sonar-scanner

ENV SONAR_RUNNER_HOME=/home/runner/sonar-scanner
ENV PATH=$PATH:/home/runner/sonar-scanner/bin

# Copy entrypoint scripts
COPY entrypoint.sh /entrypoint.sh
COPY entrypoint-org.sh /entrypoint-org.sh
RUN chmod +x /entrypoint.sh /entrypoint-org.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
