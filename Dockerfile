ARG FLAVOR_IMAGE
FROM ${FLAVOR_IMAGE}
ARG KUBECTL_VERSION=v1.21.1

COPY .versions /
RUN apk add --no-cache ca-certificates git bash curl jq sed coreutils tar && \
  . /.versions && \
  ## Install kubectl of a given version \
  ## Note: no checksum check since kubectl version is dynamic \
    ( cd /usr/local/bin && curl --retry 3 -sSLO \
        "https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
      chmod 755 kubectl ) && \
  ## Install helm \
    ( cd /tmp && file="helm-${HELM_VERSION}-linux-amd64.tar.gz" && curl -sSLO https://get.helm.sh/$file && \
      printf "${HELM_SHA}  ${file}" | sha256sum - && tar zxf ${file} && mv linux-amd64/helm /usr/local/bin/ ) && \
  ## Install helmfile \
    ( cd /usr/local/bin && curl --retry 3 -sSLo helmfile \
        "https://github.com/roboll/helmfile/releases/download/${HELMFILE_VERSION}/helmfile_linux_amd64" && \
      printf "${HELMFILE_SHA}  helmfile" | sha256sum -c && chmod 755 helmfile ) && \
  ## Install sops \
    ( cd /usr/local/bin && curl -sSLo sops \
        "https://github.com/mozilla/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux" && \
      printf "${SOPS_SHA}  sops" | sha256sum -c && chmod 755 sops ) && \
  ## Install yq \
    ( cd /usr/local/bin && curl -sSLo yq \
        "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_amd64" && \
      printf "${YQ_SHA}  yq" | sha256sum -c && chmod 755 yq ) && \
  ## Cleanup
    rm -rf /tmp/*

ARG USER=kubectl
RUN if [ "${USER}" = "kubectl" ]; then \
      mkdir /dysnix && adduser kubectl -u 1001 -D -h /dysnix/kubectl; \
    fi

USER ${USER}
WORKDIR /dysnix/kubectl

## Install plugins (already as the specified user)
RUN helm plugin install https://github.com/databus23/helm-diff && \
    helm plugin install https://github.com/futuresimple/helm-secrets && \
    helm plugin install https://github.com/hypnoglow/helm-s3.git && \
    helm plugin install https://github.com/aslafy-z/helm-git.git && \
    helm plugin install https://github.com/hayorov/helm-gcs.git

# follow DL4006 (hadolint)
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
CMD ["/usr/local/bin/kubectl"]