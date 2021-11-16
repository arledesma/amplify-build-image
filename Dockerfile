# syntax=docker/dockerfile:1.3-labs

ARG BASEIMAGE=amazonlinux
ARG BASEIMAGETAG=2
FROM ${BASEIMAGE}:${BASEIMAGETAG} as base

ENV \
    VERSION_NODE_16="16" \
    VERSION_NODE_16_EOL="2024-04-30" \
    # UTF-8 Environment
    LANGUAGE="en_US:en" \
    LANG="en_US.UTF-8" \
    LC_ALL="en_US.UTF-8" \
    # Attempt to suppress colors
    TERM="dumb"

SHELL ["/bin/bash", "--login", "-o", "pipefail", "-c"]

RUN --mount=type=tmpfs,target=/var/cache/yum \
    touch "${HOME}/.bashrc" \
    ## Install OS packages
    && yum -y update \
    # yum install -y xorg-x11-server-Xvfb gtk2-devel gtk3-devel libnotify-devel GConf2 nss libXScrnSaver alsa-lib
    && yum -y install \
        autoconf \
        automake \
        bzip2 \
        bison \
        bzr \
        cmake \
        expect \
        git \
        gcc-c++ \
        libpng \
        libpng-devel \
        libxml2 \
        libxml2-devel \
        libxslt \
        libxslt-devel \
        libyaml \
        libyaml-devel \
        nss-devel \
        openssl-devel \
        openssh-clients \
        patch \
        procps \
        python3 \
        python3-devel \
        readline-devel \
        sqlite-devel \
        tar \
        tree \
        unzip \
        wget \
        which \
        zip \
        zlib \
        zlib-devel \
    yum clean all && \
    rm -rf /var/cache/yum/*

# Framework Versions
ARG \
    VERSION_AMPLIFY="6.4.0" \
    # npm will use $VERSION_NODE_DEFAULT as the fallback if a .nvmrc is not found
    VERSION_NODE_DEFAULT="16" \
    VERSION_NVM="0.39.0" \
    NODE_DEFAULT_PACKAGES="" \
    NVM_DIR=/opt/nvm
    # NODE_DEFAULT_PACKAGES="grunt-cli bower vuepress gatsby-cli"

RUN --mount=type=tmpfs,target=/root/.cache/ \
    # Figure out the nvm install directory - could be $XDG_CONFIG_HOME/.nvm, $NVM_DIR, or $HOME/.nvm
    # NVM_INSTALL_DIR="$(realpath -m ${XDG_CONFIG_HOME:-${NVM_DIR:-$HOME}} | sed -n -e ':again' -e 's@/\.nvm$@@g;/\.nvm$/t again; p')/.nvm" \
    # Install NVM
    mkdir -p "${NVM_DIR}" \
    && curl -o- -sSL "https://raw.githubusercontent.com/nvm-sh/nvm/v${VERSION_NVM}/install.sh" | bash \
    # Configure default global packages to be installed via NVM when installing new versions of node
    && source "${NVM_DIR}/nvm.sh" \
    # SHIM for node, npm, and npx to nvm
    && chmod 755 "${NVM_DIR}/nvm-exec" \
    && install <( \
      echo '#!/usr/bin/env bash'; \
      echo '[ -z "$(nvm current 2>/dev/null || echo -n '')" ] && NODE_VERSION="\${VERSION_NODE_DEFAULT:-${VERSION_NODE_DEFAULT}}";'; \
      echo '${NVM_DIR}/nvm-exec "$@"';\
    ) /usr/bin/node \
    && ln /usr/bin/node /usr/bin/npm \
    && ln /usr/bin/node /usr/bin/npx \
    # && NVM_DEFAULT_PACKAGES_CONFIGURATION="${NVM_INSTALL_DIR}/default-packages" \
    && NVM_DEFAULT_PACKAGES_CONFIGURATION="${NPM_DIR}/default-packages" \
    && echo "Configuring NVM to install default packages:" \
    && mkdir -vp "$(dirname "${NVM_DEFAULT_PACKAGES_CONFIGURATION}")" \
    && { \
      echo "${NODE_DEFAULT_PACKAGES}" | tr " " "\n"; \
      echo "@aws-amplify/cli@${VERSION_AMPLIFY}"; \
    } | tee "$NVM_DEFAULT_PACKAGES_CONFIGURATION" \
    && mkdir -vp "${NVM_DIR}/versions/node/"

## Install Node
RUN --mount=type=tmpfs,target=/root/.cache/ \
    # Install current node LTS
    source "${NVM_DIR}/nvm.sh" \
    && LATEST_NODE_VERSION="$(nvm ls-remote --no-colors --lts "${VERSION_NODE_DEFAULT}" | awk '/Latest /{sub("->", "", $0); print $1}')" \
    && set -x \
    && ln -vs "${NVM_DIR}/versions/node/${LATEST_NODE_VERSION}" "${NVM_DIR}/versions/node/${VERSION_NODE_DEFAULT}" \
    && ls -l "${NVM_DIR}/versions/node/" \
    && ls -l "${NVM_DIR}/versions/node/${VERSION_NODE_DEFAULT}" \
    && nvm install --no-progress --latest-npm --default "$VERSION_NODE_DEFAULT" \
    && npm config -g set user $(whoami) \
    && npm config -g set unsafe-perm true \
    && nvm cache clear

ENV PATH="/root/.yarn/bin:/root/.config/yarn/global/node_modules/.bin:${NVM_DIR}/versions/node/${VERSION_NODE_DEFAULT}/bin:${PATH}"

ARG \
    VERSION_YARN="1.22.15"
RUN \
    # Install YARN
    # source ${NVM_DIR}/nvm.sh && \
    curl -o- -sSL "https://yarnpkg.com/install.sh" | bash --login -s -- --version "${VERSION_YARN}"

RUN \
    { \
      printf 'export PATH="%s";\n' "${PATH}" | tee -a "${HOME}/.bashrc" >/dev/null; \
      printf 'nvm use "%s" 1>/dev/null;\n' "${VERSION_NODE_DEFAULT}"; \
    } | tee -a "${HOME}/.bashrc" >/dev/null


ENTRYPOINT [ "bash", "-c" ]

FROM base as cypress

RUN --mount=type=tmpfs,target=/var/cache/yum \
    touch "${HOME}/.bashrc" \
    ## Install OS packages
    && yum update -y \
    && amazon-linux-extras install epel -y \
    && yum install -y \
      alsa-lib \
      chromium \
      fontconfig \
      GConf2 \
      gtk2-devel gtk3-devel \
      libffi-devel \
      libnotify-devel \
      libtool \
      libXext \
      libXScrnSaver \
      nss \
      xorg-x11-server-Xvfb \
    && yum clean all \
    && rm -rf /var/cache/yum/*

ARG \
  CYPRESS_CACHE_FOLDER="/opt/cypress" \
  VERSION_CYPRESS="9.0.0"

ENV \
  CYPRESS_CACHE_FOLDER=${CYPRESS_CACHE_FOLDER} \
  NO_COLOR=1 \
  # "fake" dbus address to prevent errors
  # https://github.com/SeleniumHQ/docker-selenium/issues/87
  DBUS_SESSION_BUS_ADDRESS=/dev/null \
  # avoid too many progress messages
  # https://github.com/cypress-io/cypress/issues/1243
  CI=1 \
  # disable shared memory X11 affecting Cypress v4 and Chrome
  # https://github.com/cypress-io/cypress-docker-images/issues/270
  QT_X11_NO_MITSHM=1 \
  _X11_NO_MITSHM=1 \
  _MITSHM=0

RUN --mount=type=tmpfs,target=/root/.cache/ \
    # Install Cypress
    source "${NVM_DIR}/nvm.sh" \
    # nvm use "${VERSION_NODE_DEFAULT}" \
    && export npm_config_unsafe_perm=true npm_config_user=root \
    && npm config set user 0 \
    && npm config set unsafe-perm true \
    && mkdir -m 1777 -p "${CYPRESS_CACHE_FOLDER}" \
    && npm install -g --allow-root cypress@${VERSION_CYPRESS} \
    && cypress install \
    && nvm cache clear

RUN --mount=type=tmpfs,target=/root/.cache/ \
    # https://github.com/aws/aws-codebuild-docker-images/blob/981cb94e134b323d626a28d41148634f20fbb5ce/al2/x86_64/standard/3.0/Dockerfile#L84-L94
    CHROME_VERSION="$(chromium-browser --version | awk -F '[ .]' '{print $2"."$3"."$4}')" \
    && CHROME_DRIVER_VERSION="$(wget -qO- "https://chromedriver.storage.googleapis.com/LATEST_RELEASE_$CHROME_VERSION")" \
    && wget -qO /root/.cache/chromedriver_linux64.zip https://chromedriver.storage.googleapis.com/$CHROME_DRIVER_VERSION/chromedriver_linux64.zip \
    && unzip -q /root/.cache/chromedriver_linux64.zip -d /opt \
    && rm /root/.cache/chromedriver_linux64.zip \
    && mv /opt/chromedriver /opt/chromedriver-$CHROME_DRIVER_VERSION \
    && chmod 755 /opt/chromedriver-$CHROME_DRIVER_VERSION \
    && ln -s /opt/chromedriver-$CHROME_DRIVER_VERSION /usr/bin/chromedriver

FROM base as node14
ARG \
    VERSION_NODE_DEFAULT="14"

ENV VERSION_NODE_14="14" \
    VERSION_NODE_14_EOL="2023-04-30"

RUN --mount=type=tmpfs,target=/root/.cache/ \
    source "${NVM_DIR}/nvm.sh" && \
    nvm install --latest-npm --default --no-progress "$VERSION_NODE_DEFAULT" \
    && ln -vs "${NVM_DIR}/versions/node/$(nvm version)" "${NVM_DIR}/versions/node/${VERSION_NODE_DEFAULT}" \
    && nvm cache clear

FROM base as awscliv2
############################
## AWSCLIv2
############################
ARG VERSION_AWSCLIV2="2.3.6"

RUN --mount=type=tmpfs,target=/root/.cache/ \
    # Install awscli v1 (/usr/local/bin/aws)
    pip3 install awscli && \
    # Install SAM CLI
    pip3 install aws-sam-cli && \
    { \
      # This should not exist in our layer but safely clean up the pip cache directory anyways
      [ -d "$(pip3 cache dir)" ] \
      && [ "$(dirname "$(pip3 cache dir)")" != "." ] \
      && [ "$(dirname "$(pip3 cache dir)")" != "/" ] \
      && rm -rf "$(pip3 cache dir)"/*; \
    }

ENV AWSCLIPATH="/opt/awscliv2"
ENV PATH="${PATH}:${AWSCLIPATH}}"

RUN --mount=type=tmpfs,target=/opt/tmpfs \
    # Install awscli v2 (${AWSCLIPATH})
    cd "/opt/tmpfs/" && \
    if [ "${VERSION_AWSCLIV2}" = "latest" ]; then awscliv2_version=""; else awscliv2_version="-${VERSION_AWSCLIV2}"; fi && \
    curl -sSL -o "/opt/tmpfs/awscliv2.zip" "https://awscli.amazonaws.com/awscli-exe-linux-x86_64${awscliv2_version}.zip" && \
    unzip "/opt/tmpfs/awscliv2.zip" && \
    /opt/tmpfs/aws/install --bin-dir "${AWSCLIPATH}/" && \
    rm -rf "/opt/tmpfs/aws" "/opt/tmpfs/awscliv2.zip" && \
    cd "/root"

RUN { \
      echo -n "# awscliv2 "; \
      printf '#PATH# "%s";\n' "${AWSCLIPATH}"; \
      printf 'export PATH="%s";\n' "${PATH}"; \
    } | tee -a "${HOME}/.bashrc" >/dev/null

FROM base as hugo
############################
## HUGO
############################
ARG VERSION_HUGO="0.89.2"

RUN --mount=type=tmpfs,target=/opt/tmpfs \
    cd "/opt/tmpfs" && \
    ## Install Hugo
    curl -sSL -o "/opt/tmpfs/hugo.tar.gz" "https://github.com/gohugoio/hugo/releases/download/v${VERSION_HUGO}/hugo_${VERSION_HUGO}_Linux-64bit.tar.gz" && \
    tar -xf "/opt/tmpfs/hugo.tar.gz" hugo -C /opt/tmpfs/ && \
    mv "/opt/tmpfs/hugo" "/usr/bin/hugo" && \
    rm -rf "/opt/tmpfs/hugo.tar.gz" && \
    ## Install Hugo Extended Sass/SCSS support
    curl -sSL -o "/opt/tmpfs/hugo_extended.tar.gz" "https://github.com/gohugoio/hugo/releases/download/v${VERSION_HUGO}/hugo_extended_${VERSION_HUGO}_Linux-64bit.tar.gz" && \
    tar -xf "/opt/tmpfs/hugo_extended.tar.gz" hugo -C /opt/tmpfs/ && \
    mv "/opt/tmpfs/hugo" "/usr/bin/hugo_extended" && \
    rm -rf "/opt/tmpfs/hugo_extended.tar.gz" && \
    cd "/root"


FROM base as ruby
############################
## RUBY
############################

ENV \
    VERSION_RUBY_2_6="2.6.8" \
    VERSION_RUBY_2_6_EOL="2022-03-31" \
    VERSION_RUBY_2_7="2.7.4" \
    VERSION_RUBY_2_7_EOL="2023-03-31" \
    VERSION_RUBY_3_0="3.0.2" \
    VERSION_RUBY_3_0_EOL="2024-03-31" \
    VERSION_BUNDLER="2.2.31"

ENV VERSION_RUBY_DEFAULT=${VERSION_RUBY_3_0}

## Install RVM
RUN gpg --keyserver keyserver.ubuntu.com \
      --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB && \
	  curl -sL https://get.rvm.io | bash -s stable --with-gems="bundler"

ENV PATH="/usr/local/rvm/bin:${PATH}"

RUN /bin/bash --login -c ' \
  declare -a RUBY_VERSIONS=(${VERSION_RUBY_2_6} ${VERSION_RUBY_2_7} ${VERSION_RUBY_3_0}); \
  for ruby_version in ${RUBY_VERSIONS[@]}; do \
    echo rvm install "${ruby_version}"; \
	  rvm install "${ruby_version}" && rvm use "${ruby_version}" && gem install bundler -v "${VERSION_BUNDLER}" && gem install jekyll; \
  done && \
	for cleanup_target in archives repos sources logs; do \
      echo rvm cleanup "${cleanup_target}"; \
      rvm cleanup "${cleanup_target}"; \
  done'

ENV RUBYPATH="/usr/local/rvm/gems/ruby-${VERSION_RUBY_DEFAULT}/bin:/usr/local/rvm/gems/ruby-${VERSION_RUBY_DEFAULT}@global/bin:/usr/local/rvm/rubies/ruby-${VERSION_RUBY_DEFAULT}/bin:/usr/local/rvm/bin" \
    GEM_PATH="/usr/local/rvm/gems/ruby-${VERSION_RUBY_DEFAULT}"
ENV PATH="${RUBYPATH}:${PATH}"

## Environment Setup
RUN { \
      echo ''; \
      echo -n "# ruby "; \
      printf '#PATH# "%s";\n' "${RUBYPATH}"; \
      printf 'export PATH="%s";\n' "${PATH}"; \
      printf 'export GEM_PATH="/usr/local/rvm/gems/ruby-%s";\n' "${VERSION_RUBY_DEFAULT}"; \
    } | tee -a "${HOME}/.bashrc" >/dev/null

FROM ruby as kitchensink
############################
## KITCHENSINK
############################

COPY --from=node14 "/opt/nvm/versions/node/" "/opt/nvm/versions/node/"
COPY --from=cypress "/opt/cypress/" "/opt/cypress/"
COPY --from=awscliv2 "/opt/awscliv2/" "/opt/awscliv2/"
COPY --from=awscliv2 "/usr/local/aws-cli/" "/usr/local/aws-cli/"
COPY --from=hugo "/usr/bin/hugo" "/usr/bin/hugo_extended" /usr/bin/

RUN --mount=type=bind,from=awscliv2,source=/root,target=/source \
  { \
    echo ''; \
    echo -n "# awscliv2 "; \
    grep '#PATH# ' "/source/.bashrc" || echo ""; \
    sed -n '/#PATH# /{s/#PATH# //p}' "/source/.bashrc" | xargs -n1 -I{} echo 'export PATH="${PATH}:{}";'; \
    echo ''; \
  } | tee -a "${HOME}/.bashrc"

RUN --mount=type=bind,from=hugo,source=/root,target=/source \
  { \
    echo -n "# hugo "; \
    grep '#PATH# ' "/source/.bashrc" || echo ""; \
    sed -n '/#PATH# /{s/#PATH# //p}' "/source/.bashrc" | xargs -n1 -I{} echo 'export PATH="${PATH}:{}";'; \
    echo ''; \
  } | tee -a "${HOME}/.bashrc"

RUN tee -a "${HOME}/.bashrc" >/dev/null <<_EOF_
PATH="\$(printf %s "\$PATH" | awk -v RS=: '{ if (!arr[\$0]++) {printf("%s%s",!ln++?"":":",\$0)}}')";
export PATH;
_EOF_