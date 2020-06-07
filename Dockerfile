FROM alpine:3.12

ARG KUBECTL_VERSION
ENV HELM_VERSION="v3.2.1" \
    HELM_SHA256="018f9908cb950701a5d59e757653a790c66d8eda288625dbb185354ca6f41f6b" \
    HELMFILE_VERSION="v0.118.5" \
    HELMFILE_SHA256="12098f97be06ccda3af2707f1b0ef78038ebf5e47a1a6db9da35691724157916" \
    SOPS_VERSION="v3.5.0" \
    SOPS_SHA256="610fca9687d1326ef2e1a66699a740f5dbd5ac8130190275959da737ec52f096"

RUN apk add --no-cache ca-certificates git bash curl jq sed coreutils && \
  ## Install kubectl of a given version \
    ( cd /usr/local/bin && curl --retry 3 -sSLO \
        "https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
      chmod 755 kubectl ) && \
  ## Install helm \
    ( cd /tmp && file="helm-${HELM_VERSION}-linux-amd64.tar.gz" && curl -sSLO https://get.helm.sh/$file && \
      sha256sum ${file} && tar zxf ${file} && mv linux-amd64/helm /usr/local/bin/ ) && \
  ## Install helmfile \
    ( cd /usr/local/bin && curl --retry 3 -sSLo helmfile \
        "https://github.com/roboll/helmfile/releases/download/${HELMFILE_VERSION}/helmfile_linux_amd64" && \
      printf "${HELMFILE_SHA256}  helmfile" | sha256sum -c && chmod 755 helmfile ) && \
  ## Install sops \
    ( cd /usr/local/bin && curl -sSLo sops \
        "https://github.com/mozilla/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux" && \
      printf "${SOPS_SHA256}  sops" | sha256sum -c && chmod 755 sops ) && \
  ## Cleanup
    rm -rf /tmp/*

RUN adduser kubectl -u 1001 -D
USER kubectl
WORKDIR /home/kubectl

## Install plugins (unprivilged)
RUN helm plugin install https://github.com/databus23/helm-diff --version v3.1.1 && \
    helm plugin install https://github.com/futuresimple/helm-secrets && \
    helm plugin install https://github.com/hypnoglow/helm-s3.git && \
    helm plugin install https://github.com/aslafy-z/helm-git.git

CMD ["/usr/local/bin/kubectl"]
