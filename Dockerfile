ARG FLAVOR_IMAGE
FROM ${FLAVOR_IMAGE}
ARG KUBECTL_VERSION=v1.24.0
# auto-populated by buildkit
ARG TARGETARCH
ENV ARCH=${TARGETARCH:-amd64}

# follow DL4006 (hadolint)
SHELL ["/bin/sh", "-o", "pipefail", "-c"]

ENV GOSU_VERSION 1.17
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

## Install system packages
RUN apk add --no-cache ca-certificates git bash curl wget jq sed coreutils tar sudo shadow

## Make kubectl user the passwordless sudoer
RUN mkdir /dysnix && adduser kubectl -u 1001 -D -h /dysnix/kubectl; \
    groupadd -r sudo && \
    usermod -aG sudo kubectl && \
    echo "%sudo   ALL=(ALL:ALL) NOPASSWD:ALL" >> /etc/sudoers

## Install kubectl of a given version \
## Note: no checksum check since kubectl version is dynamic \
RUN \
  ( cd /usr/local/bin && curl --retry 3 -sSLO \
        "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" && \
      chmod 755 kubectl ) && \
  # expose PATH via profile \
  if [ -d "/google-cloud-sdk/bin" ]; then \
    echo "PATH=/google-cloud-sdk/bin:\$PATH" >> /etc/profile.d/google-cloud-sdk.sh; \
  fi

## Install tools
COPY .versions.${ARCH} /.versions
RUN . /.versions && \
  ## Install helm \
    ( cd /tmp && file="helm-${HELM_VERSION}-linux-${ARCH}.tar.gz" && curl -sSLO https://get.helm.sh/$file && \
      printf "${HELM_SHA}  ${file}" | sha256sum - && tar zxf ${file} && mv linux-${ARCH}/helm /usr/local/bin/ ) && \
  ## Install helmfile \
    ( cd /tmp && file="helmfile_${HELMFILE_VERSION//v/}_linux_${ARCH}.tar.gz" && curl --retry 3 -sSLO \
        "https://github.com/helmfile/helmfile/releases/download/${HELMFILE_VERSION}/$file" && \
      printf "${HELMFILE_SHA} ${file}" | sha256sum -c && tar zxf ${file} && mv helmfile /usr/local/bin/ ) && \
  ## Install sops \
    ( cd /usr/local/bin && curl -sSLo sops \
        "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.${ARCH}" && \
      printf "${SOPS_SHA}  sops" | sha256sum -c && chmod 755 sops ) && \
  ## Install yq \
    ( cd /usr/local/bin && curl -sSLo yq \
        "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${ARCH}" && \
      printf "${YQ_SHA}  yq" | sha256sum -c && chmod 755 yq ) && \
    rm -rf /tmp/* /var/cache/apk

## Install plugins (already as the specified user)
RUN sudo -iu kubectl bash -c 'set -e; \
      helm plugin install https://github.com/databus23/helm-diff; \
      helm plugin install https://github.com/jkroepke/helm-secrets; \
      helm plugin install https://github.com/hypnoglow/helm-s3.git; \
      helm plugin install https://github.com/aslafy-z/helm-git.git; \
      helm plugin install https://github.com/hayorov/helm-gcs.git; \
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
