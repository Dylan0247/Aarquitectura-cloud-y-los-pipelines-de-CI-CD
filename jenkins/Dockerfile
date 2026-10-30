FROM jenkins/jenkins:lts-jdk21

USER root
ARG TERRAFORM_VERSION=1.17.0
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl unzip python3 python3-venv \
    && rm -rf /var/lib/apt/lists/*
RUN set -eu; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in amd64|arm64) ;; *) exit 1 ;; esac; \
    mkdir /tmp/tf-install; cd /tmp/tf-install; \
    base="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}"; \
    curl -fsSLO "$base/terraform_${TERRAFORM_VERSION}_linux_${arch}.zip"; \
    curl -fsSLO "$base/terraform_${TERRAFORM_VERSION}_SHA256SUMS"; \
    grep " terraform_${TERRAFORM_VERSION}_linux_${arch}.zip$" "terraform_${TERRAFORM_VERSION}_SHA256SUMS" > selected.sha256; \
    sha256sum -c selected.sha256; \
    unzip "terraform_${TERRAFORM_VERSION}_linux_${arch}.zip" terraform -d /usr/local/bin; \
    cd /; rm -rf /tmp/tf-install
RUN python3 -m venv /opt/awscli \
    && /opt/awscli/bin/pip install --no-cache-dir awscli \
    && ln -s /opt/awscli/bin/aws /usr/local/bin/aws
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
USER jenkins
