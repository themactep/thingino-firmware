# syntax=docker/dockerfile:1

FROM debian:trixie

# Build arguments
ARG USER_ID=1000
ARG GROUP_ID=1000
ARG USERNAME=builder

# Install build dependencies
RUN DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC apt-get update && \
    DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC apt-get install -y \
    ack apt-utils apt-transport-https autoconf bc bison build-essential \
    busybox ca-certificates ccache cmake cpio curl dialog file flex fzf \
    gawk git golang-go libcrypt-dev libncurses-dev locales lzop \
    m4 mc nano perl python3 python3-jinja2 python3-jsonschema python3-yaml \
    rsync ssh sudo toilet u-boot-tools unzip vim wget whiptail && \
    rm -rf /var/lib/apt/lists/*

# Set vim as default editor
RUN update-alternatives --install /usr/bin/editor editor /usr/bin/vim 1 && \
    update-alternatives --set editor /usr/bin/vim && \
    update-alternatives --install /usr/bin/vi vi /usr/bin/vim 1 && \
    update-alternatives --set vi /usr/bin/vim

# Update CA certificates
RUN update-ca-certificates

# Configure and generate locale
RUN echo "en_US.UTF-8 UTF-8" > /etc/locale.gen && \
    locale-gen en_US.UTF-8 && \
    update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

# Create user with matching UID/GID for volume permissions
RUN groupadd -g ${GROUP_ID} ${USERNAME} && \
    useradd -m -u ${USER_ID} -g ${GROUP_ID} -s /bin/bash ${USERNAME} && \
    echo "${USERNAME}:${USERNAME}" | chpasswd && \
    echo "${USERNAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER ${USERNAME}

# Set up Buildroot download cache directory
ENV BR2_DL_DIR=/home/${USERNAME}/dl

# Set working directory
WORKDIR /home/${USERNAME}/build

# Configure git
RUN git config --global --add safe.directory /home/${USERNAME}/build && \
    git config --global alias.up 'pull --rebase --autostash'

# Default command
CMD ["/bin/bash"]
