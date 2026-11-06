FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    clang \
    flex \
    bison \
    g++ \
    gawk \
    gettext \
    git \
    libncurses5-dev \
    libssl-dev \
    python3 \
    python3-distutils \
    rsync \
    unzip \
    zlib1g-dev \
    file \
    wget \
    sudo \
    curl \
    && if [ "$(dpkg --print-architecture)" = amd64 ]; then apt-get install -y gcc-multilib; fi \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash builder && \
    echo "builder ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

USER builder
WORKDIR /home/builder/workspace

ENTRYPOINT ["/bin/bash"]
