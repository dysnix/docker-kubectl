ARG FLAVOR_IMAGE
FROM ${FLAVOR_IMAGE}
ARG KUBECTL_VERSION=v1.21.2

# follow DL4006 (hadolint)
SHELL ["/bin/sh", "-o", "pipefail", "-c"]

ENV GOSU_VERSION 1.14
RUN set -eux; \
	\
	apk add --no-cache --virtual .gosu-deps \
		ca-certificates \
		dpkg \
		gnupg \
	; \
	\
	dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
	wget -O /usr/local/bin/gosu "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch"; \
	wget -O /usr/local/bin/gosu.asc "https://github.com/tianon/gosu/releases/download/$GOSU_VERSION/gosu-$dpkgArch.asc"; \
	\
# verify the signature
	export GNUPGHOME="$(mktemp -d)"; \
	gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4; \
	gpg --batch --verify /usr/local/bin/gosu.asc /usr/local/bin/gosu; \
	command -v gpgconf && gpgconf --kill all || :; \
	rm -rf "$GNUPGHOME" /usr/local/bin/gosu.asc; \
	\
# clean up fetch dependencies
	apk del --no-network .gosu-deps; \
	\
	chmod +x /usr/local/bin/gosu; \
# verify that the binary works
	gosu --version; \
	gosu nobody true

## Install tooling
##
COPY .versions /
RUN apk add --no-cache ca-certificates git bash curl wget jq sed coreutils tar sudo && \
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
    rm -rf /tmp/* /var/cache/apk

## Extend profile.d for "in-docker" github-actions (container's environment variables are obscured)
##
RUN \
  if [ -d "/google-cloud-sdk/bin" ]; then \
    echo "PATH=/google-cloud-sdk/bin:\$PATH" >> /etc/profile.d/google-cloud-sdk.sh; \
  fi

## Make kubectl user the passwordless sudoer
RUN mkdir /dysnix && adduser kubectl -u 1001 -D -h /dysnix/kubectl; \
    groupadd -r sudo && \
    usermod -aG sudo kubectl && \
    echo "%sudo   ALL=(ALL:ALL) NOPASSWD:ALL" >> /etc/sudoers

## Install plugins (already as the specified user)
RUN sudo -iu kubectl bash -c 'set -e\
      helm plugin install https://github.com/databus23/helm-diff \
      helm plugin install https://github.com/futuresimple/helm-secrets \
      helm plugin install https://github.com/hypnoglow/helm-s3.git \
      helm plugin install https://github.com/aslafy-z/helm-git.git \
      helm plugin install https://github.com/hayorov/helm-gcs.git \
    '

## Set cache and home for helme (useful for environments which override HOME)
ENV \
  HELM_CACHE_HOME=/dysnix/kubectl/.cache/helm \
  HELM_DATA_HOME=/dysnix/kubectl/.local/share/helm

SHELL ["/bin/bash", "-lo", "pipefail", "-c"]
WORKDIR /dysnix/kubectl
CMD ["/usr/local/bin/kubectl"]

## NOTE: When using on CI environments make sure there UIDs match.
## ref:  https://github.com/tianon/gosu 
##
##       Example: sudo gosu 1000:1000 command
USER kubectl
