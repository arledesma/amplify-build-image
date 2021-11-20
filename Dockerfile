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

SHELL ["/bin/bash", "--login", "-e", "-o", "pipefail", "-c"]

RUN --mount=type=tmpfs,target=/var/cache/yum <<RUN_EOT
  touch "${HOME}/.bashrc"
  ## Install OS packages
  yum update -y
  yum install -y \
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
    zlib-devel
  yum clean all
  rm -rf /var/cache/yum/*
RUN_EOT

# Framework Versions
ARG \
    VERSION_AMPLIFY="6.4.0" \
    # npm will use $VERSION_NODE_DEFAULT as the fallback if a .nvmrc is not found
    VERSION_NODE_DEFAULT="16" \
    VERSION_NVM="0.39.0" \
    NODE_DEFAULT_PACKAGES="" \
    NVM_DIR=/opt/nvm
    # NODE_DEFAULT_PACKAGES="grunt-cli bower vuepress gatsby-cli"

# SC2016: "Expressions don't expand in single quotes, use double quotes for that." -- ${VERSION_NODE_DEFAULT} is expanded by docker
# hadolint ignore=SC2016
RUN --mount=type=tmpfs,target=/root/.cache/ <<RUN_EOT
  # Install NVM
  mkdir -p "${NVM_DIR}"
  curl -o- -sSL "https://raw.githubusercontent.com/nvm-sh/nvm/v${VERSION_NVM}/install.sh" | bash
  # Configure default global packages to be installed via NVM when installing new versions of node
  source "${NVM_DIR}/nvm.sh"
  # SHIM for node, npm, and npx to nvm
  chmod 755 "${NVM_DIR}/nvm-exec"
  install <(
    echo '#!/usr/bin/env bash';
    echo '[ -z "$(nvm current 2>/dev/null || echo -n '')" ] && NODE_VERSION="\${VERSION_NODE_DEFAULT:-${VERSION_NODE_DEFAULT}}";';
    echo '${NVM_DIR}/nvm-exec "$@"';
  ) /usr/bin/node
  ln /usr/bin/node /usr/bin/npm
  ln /usr/bin/node /usr/bin/npx
  NVM_DEFAULT_PACKAGES_CONFIGURATION="${NPM_DIR}/default-packages"
  echo "Configuring NVM to install default packages:"
  mkdir -vp "$(dirname "${NVM_DEFAULT_PACKAGES_CONFIGURATION}")"
  {
    echo "${NODE_DEFAULT_PACKAGES}" | tr " " "\n";
    echo "@aws-amplify/cli@${VERSION_AMPLIFY}";
  } | tee "$NVM_DEFAULT_PACKAGES_CONFIGURATION"
  mkdir -vp "${NVM_DIR}/versions/node/"
RUN_EOT

## Install Node
RUN --mount=type=tmpfs,target=/root/.cache/ <<RUN_EOT
  # Install current node LTS
  source "${NVM_DIR}/nvm.sh"
  LATEST_NODE_VERSION="$(nvm ls-remote --no-colors --lts "${VERSION_NODE_DEFAULT}" | awk '/Latest /{sub("->", "", $0); print $1}')"
  set -x
  ln -vs "${NVM_DIR}/versions/node/${LATEST_NODE_VERSION}" "${NVM_DIR}/versions/node/${VERSION_NODE_DEFAULT}"
  ls -l "${NVM_DIR}/versions/node/"
  ls -l "${NVM_DIR}/versions/node/${VERSION_NODE_DEFAULT}"
  nvm install --no-progress --latest-npm --default "$VERSION_NODE_DEFAULT"
  npm config -g set user "$(whoami)"
  npm config -g set unsafe-perm true
  nvm cache clear
RUN_EOT

ENV PATH="/root/.yarn/bin:/root/.config/yarn/global/node_modules/.bin:${NVM_DIR}/versions/node/${VERSION_NODE_DEFAULT}/bin:${PATH}"

ARG \
    VERSION_YARN="1.22.15"
RUN <<RUN_EOT
  # Install YARN
  source "${NVM_DIR}/nvm.sh"
  curl -o- -sSL "https://yarnpkg.com/install.sh" | bash --login -s -- --version "${VERSION_YARN}"
RUN_EOT

RUN <<RUN_EOT
  {
    printf 'export PATH="%s";\n' "${PATH}" | tee -a "${HOME}/.bashrc" >/dev/null;
    printf 'nvm use "%s" 1>/dev/null;\n' "${VERSION_NODE_DEFAULT}";
  } | tee -a "${HOME}/.bashrc" >/dev/null
RUN_EOT

ENTRYPOINT [ "bash", "-c" ]

FROM base as cypress

RUN --mount=type=tmpfs,target=/var/cache/yum <<RUN_EOT
  ## Install OS packages
  yum update -y
  amazon-linux-extras install epel -y
  yum install -y \
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
    xorg-x11-server-Xvfb
  yum clean all
  rm -rf /var/cache/yum/*
RUN_EOT

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

# SC2174 - "When used with -p, -m only applies to the deepest directory." - We only need the permission of the deepest directory to be set for ${CYPRESS_CACHE_FOLDER}
# hadolint ignore=SC2174
RUN --mount=type=tmpfs,target=/root/.cache/ <<RUN_EOT
  # Install Cypress
  source "${NVM_DIR}/nvm.sh"
  # nvm use "${VERSION_NODE_DEFAULT}"
  npm config -g set user "$(whoami)"
  npm config -g set unsafe-perm true
  mkdir -m 1777 -p "${CYPRESS_CACHE_FOLDER}"
  npm install -g --allow-root "cypress@${VERSION_CYPRESS}"
  cypress install
  nvm cache clear
RUN_EOT

RUN --mount=type=tmpfs,target=/root/.cache/ <<RUN_EOT
  # https://github.com/aws/aws-codebuild-docker-images/blob/981cb94e134b323d626a28d41148634f20fbb5ce/al2/x86_64/standard/3.0/Dockerfile#L84-L94
  CHROME_VERSION="$(chromium-browser --version | awk -F '[ .]' '{print $2"."$3"."$4}')"
  CHROME_DRIVER_VERSION="$(wget -qO- "https://chromedriver.storage.googleapis.com/LATEST_RELEASE_$CHROME_VERSION")"
  wget -qO /root/.cache/chromedriver_linux64.zip "https://chromedriver.storage.googleapis.com/$CHROME_DRIVER_VERSION/chromedriver_linux64.zip"
  unzip -q /root/.cache/chromedriver_linux64.zip -d /opt
  rm /root/.cache/chromedriver_linux64.zip
  mv /opt/chromedriver "/opt/chromedriver-$CHROME_DRIVER_VERSION"
  chmod 755 "/opt/chromedriver-$CHROME_DRIVER_VERSION"
  ln -s "/opt/chromedriver-$CHROME_DRIVER_VERSION" /usr/bin/chromedriver
RUN_EOT

FROM base as node14
ARG \
    VERSION_NODE_DEFAULT="14"

ENV VERSION_NODE_14="14" \
    VERSION_NODE_14_EOL="2023-04-30"

RUN --mount=type=tmpfs,target=/root/.cache/ <<RUN_EOT
  source "${NVM_DIR}/nvm.sh"
  nvm install --latest-npm --default --no-progress "$VERSION_NODE_DEFAULT"
  ln -vs "${NVM_DIR}/versions/node/$(nvm version)" "${NVM_DIR}/versions/node/${VERSION_NODE_DEFAULT}"
  nvm cache clear
RUN_EOT

FROM base as awscliv2
############################
## AWSCLIv2
############################
ARG VERSION_AWSCLIV2="2.3.6"

# DL3013 - "Pin versions in pip. Instead of `pip install <package>` use `pip install <package>==<version>` or `pip install --requirement <requirements file>`"
# hadolint ignore=DL3013
RUN --mount=type=tmpfs,target=/root/.cache/ <<RUN_EOT
  # Install awscli v1 (/usr/local/bin/aws)
  # --no-cache-dir is redundant with the tmpfs mounted to /root/.cache but we do not have to worry about pip moving the cache directory with the argument
  pip3 install --no-cache-dir awscli
  # Install SAM CLI
  pip3 install --no-cache-dir aws-sam-cli
  {
    # This should not exist in our layer but safely clean up the pip cache directory anyways
    pipcachedir="$(pip3 cache dir)";
    [ -d "${pipcachedir}" ] && \
    [ "$(dirname "${pipcachedir}")" != "." ] && \
    [ "$(dirname "${pipcachedir}")" != "/" ] && \
    rm -rf "${pipcachedir:?}"/*;
  }
RUN_EOT

ENV AWSCLIPATH="/opt/awscliv2"
ENV PATH="${PATH}:${AWSCLIPATH}}"

RUN --mount=type=tmpfs,target=/opt/tmpfs <<RUN_EOT
  # Install awscli v2 (${AWSCLIPATH})
  cd "/opt/tmpfs/" || exit 1
  if [ "${VERSION_AWSCLIV2}" = "latest" ]; then awscliv2_version=""; else awscliv2_version="-${VERSION_AWSCLIV2}"; fi
  curl -sSL -o "/opt/tmpfs/awscliv2.zip" "https://awscli.amazonaws.com/awscli-exe-linux-x86_64${awscliv2_version}.zip"
  unzip "/opt/tmpfs/awscliv2.zip" && \
  /opt/tmpfs/aws/install --bin-dir "${AWSCLIPATH}/"
  rm -rf "/opt/tmpfs/aws" "/opt/tmpfs/awscliv2.zip"
  cd "/root" || exit 1
RUN_EOT

RUN <<RUN_EOT
  {
    printf '\n# awscliv2 #PATH# "%s"\n' "${AWSCLIPATH}";
    printf 'export PATH="%s";\n' "${PATH}";
  } | tee -a "${HOME}/.bashrc" >/dev/null
RUN_EOT

FROM base as hugo
############################
## HUGO
############################
ARG VERSION_HUGO="0.89.2"

RUN --mount=type=tmpfs,target=/opt/tmpfs <<RUN_EOT
  cd "/opt/tmpfs" || exit 1
  ## Install Hugo
  curl -sSL -o "/opt/tmpfs/hugo.tar.gz" "https://github.com/gohugoio/hugo/releases/download/v${VERSION_HUGO}/hugo_${VERSION_HUGO}_Linux-64bit.tar.gz"
  tar -xf "/opt/tmpfs/hugo.tar.gz" hugo -C /opt/tmpfs/
  mv "/opt/tmpfs/hugo" "/usr/bin/hugo"
  rm -rf "/opt/tmpfs/hugo.tar.gz"
  ## Install Hugo Extended Sass/SCSS support
  curl -sSL -o "/opt/tmpfs/hugo_extended.tar.gz" "https://github.com/gohugoio/hugo/releases/download/v${VERSION_HUGO}/hugo_extended_${VERSION_HUGO}_Linux-64bit.tar.gz"
  tar -xf "/opt/tmpfs/hugo_extended.tar.gz" hugo -C /opt/tmpfs/
  mv "/opt/tmpfs/hugo" "/usr/bin/hugo_extended"
  rm -rf "/opt/tmpfs/hugo_extended.tar.gz"
  cd "/root" || exit 1
RUN_EOT

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
RUN <<RUN_EOT
  gpg --keyserver keyserver.ubuntu.com --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB
  curl -sL https://get.rvm.io | bash -s stable --with-gems="bundler"
RUN_EOT

ENV PATH="/usr/local/rvm/bin:${PATH}"

RUN <<-"RUN_EOT"
  #/usr/bin/env -S bash --login
  declare -a RUBY_VERSIONS=(${VERSION_RUBY_2_6} ${VERSION_RUBY_2_7} ${VERSION_RUBY_3_0});
  for ruby_version in ${RUBY_VERSIONS[@]}; do
    echo rvm install "${ruby_version}";
    rvm install "${ruby_version}";
    rvm use "${ruby_version}";
    gem install bundler -v "${VERSION_BUNDLER}";
    # gem install jekyll;
    # #16 290.3 unknown encoding name "chunked\r\n\r\n25" for ext/ruby_http_parser/vendor/http-parser-java/tools/parse_tests.rb, skipping
    # 16 318.7 Before reporting this, could you check that the file you're documenting
    # #16 318.7 has proper syntax:
    # #16 318.7
    # #16 318.7   /usr/local/rvm/rubies/ruby-2.6.8/bin/ruby -c lib/jekyll/commands/doctor.rb
    # #16 318.7
    # #16 318.7 RDoc is not a full Ruby parser and will fail when fed invalid ruby programs.
    # #16 318.7
    # #16 318.7 The internal error was:
    # #16 318.7
    # #16 318.7       (NoMethodError) undefined method `[]' for nil:NilClass
    # #16 318.7
    # #16 318.7 ERROR:  While executing gem ... (NoMethodError)
    # #16 318.7     undefined method `[]' for nil:NilClass
    # '
  done
  for cleanup_target in archives repos sources logs; do
      echo rvm cleanup "${cleanup_target}";
      rvm cleanup "${cleanup_target}";
  done
RUN_EOT

ENV RUBYPATH="/usr/local/rvm/gems/ruby-${VERSION_RUBY_DEFAULT}/bin:/usr/local/rvm/gems/ruby-${VERSION_RUBY_DEFAULT}@global/bin:/usr/local/rvm/rubies/ruby-${VERSION_RUBY_DEFAULT}/bin:/usr/local/rvm/bin" \
    GEM_PATH="/usr/local/rvm/gems/ruby-${VERSION_RUBY_DEFAULT}"
ENV PATH="${RUBYPATH}:${PATH}"

## Environment Setup
RUN <<RUN_EOT
  {
    printf '\n# ruby #PATH# "%s"\n' "${RUBYPATH}";
    printf 'export PATH="%s";\n' "${PATH}";
    printf 'export GEM_PATH="/usr/local/rvm/gems/ruby-%s";\n' "${VERSION_RUBY_DEFAULT}";
  } | tee -a "${HOME}/.bashrc" >/dev/null
RUN_EOT

FROM ruby as kitchensink
############################
## KITCHENSINK
############################

COPY --from=node14 "/opt/nvm/versions/node/" "/opt/nvm/versions/node/"
COPY --from=cypress "/opt/cypress/" "/opt/cypress/"
COPY --from=awscliv2 "/opt/awscliv2/" "/opt/awscliv2/"
COPY --from=awscliv2 "/usr/local/aws-cli/" "/usr/local/aws-cli/"
COPY --from=hugo "/usr/bin/hugo" "/usr/bin/hugo_extended" /usr/bin/

# SC2016: "Expressions don't expand in single quotes, use double quotes for that." -- ${PATH} should not be expanded until runtime
# hadolint ignore=SC2016
RUN --mount=type=bind,from=awscliv2,source=/root,target=/source <<RUN_EOT
  {
    echo '';
    grep '#PATH# ' "/source/.bashrc" || echo "";
    sed -n '/#PATH# /{s/.*#PATH# //p}' "/source/.bashrc" | xargs -n1 -I{} echo 'export PATH="\${PATH}:{}";';
    echo '';
  } | tee -a "${HOME}/.bashrc"
RUN_EOT

RUN <<RUN_EOT
#!/usr/bin/env bash
# HEREDOC in Dockerfile is not correctly honoring <<- which was leading to the HEREDOC for tee to not end correctly
# this was then adding '_EOF_' to the end of the file, causing an error when starting bash
  tee -a "${HOME}/.bashrc" >/dev/null <<-_EOF_
# remove duplicates and sanitize path
PATH="\$(printf %s "\$PATH" | awk -v RS=: '{ if (!arr[\$0]++) {printf("%s%s",!ln++?"":":",\$0)}}')";
export PATH;
_EOF_
RUN_EOT
