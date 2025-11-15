FROM alpine

# Install sudo + basic tools
RUN apk add --no-cache \
    bash \
    curl \
    python3 \
    py3-pip \
    sed \
    openssh \
    openssh-client \
    jq \
    sudo \
    aws-cli \
    py3-cryptography

COPY build.sh .

ADD BP-BASE-SHELL-STEPS .

# Use key=value format for ENV
ENV SSH_CREDENTIAL_NAME="SSH_KEY"
ENV PROXY_OPTION=""
ENV SSH_USERNAME=""
ENV SSH_IP=""
ENV SSH_PORT="22"
ENV PROXY_SERVER_IP=""
ENV SLEEP_DURATION="5s"
ENV ACTIVITY_SUB_TASK_CODE="MANAGE_REMOTE_PROCESS"
ENV VALIDATION_FAILURE_ACTION="WARNING"
ENV ACTION="status"

ENTRYPOINT ["./build.sh"]
