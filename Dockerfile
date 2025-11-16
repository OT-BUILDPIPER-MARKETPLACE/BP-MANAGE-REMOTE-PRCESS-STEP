FROM alpine


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


ENV SSH_CREDENTIAL_NAME="SSH_KEY" \
    PROXY_OPTION="" \
    SSH_USERNAME="" \
    SSH_IP="" \
    SSH_PORT="22" \
    PROXY_SERVER_IP="" \
    SLEEP_DURATION="5s" \
    ACTIVITY_SUB_TASK_CODE="MANAGE_REMOTE_PROCESS" \
    VALIDATION_FAILURE_ACTION="WARNING" \
    ACTION="status"

RUN addgroup -g 65522 buildpiper && \
    adduser -D -u 65522 -G buildpiper -h /home/buildpiper buildpiper && \
    mkdir -p /home/buildpiper && \
    chown -R buildpiper:buildpiper /home/buildpiper


RUN mkdir -p \
        /src/reports \
        /bp/data \
        /bp/execution_dir \
        /opt/buildpiper/shell-functions \
        /opt/buildpiper/data \
        /bp/workspace && \
    chown -R buildpiper:buildpiper /src /bp /opt


COPY --chown=buildpiper:buildpiper build.sh /home/buildpiper/build.sh
COPY --chown=buildpiper:buildpiper BP-BASE-SHELL-STEPS /opt/buildpiper/shell-functions/

RUN chmod +x /home/buildpiper/build.sh && \
    mkdir -p /home/buildpiper/reports && \
    chown -R buildpiper:buildpiper /home/buildpiper

USER buildpiper

WORKDIR /home/buildpiper

ENTRYPOINT ["./build.sh"]
