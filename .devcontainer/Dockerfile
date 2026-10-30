FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive

# Copy package lists
COPY apt-packages.txt /tmp/apt-packages.txt

# Install packages
RUN apt-get update && \
    xargs -a /tmp/apt-packages.txt apt-get install -y && \
    rm -rf /var/lib/apt/lists/*

# Generate and set locale
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# Create user
RUN usermod -a -G root ubuntu
RUN usermod -a -G sudo ubuntu

# Allow user to use sudo without a password
RUN echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu

# Create RTEMS directory
RUN mkdir -p /opt/rtems && \
    chown -R ubuntu:ubuntu /opt/rtems

USER ubuntu

# Create and activate venv
RUN cd /opt/rtems && \
    python3 -m venv venv

# Install further packages (none at the moment)
RUN /opt/rtems/venv/bin/pip install --upgrade pip

# Add the virtual environment to PATH
ENV VIRTUAL_ENV="/opt/rtems/venv"
ENV PATH="$VIRTUAL_ENV/bin:/opt/rtems/6/bin:$PATH"

# Automatically activate the virtual environment in .bashrc
RUN echo "source /opt/rtems/venv/bin/activate" >> /home/ubuntu/.bashrc

# Build RTEMS
RUN cd /opt/rtems && \
    mkdir src && \
    cd src && \
    wget https://github.com/RTEMS/rtems-source-builder/archive/refs/tags/6.2.tar.gz -O - | tar xzf - && \
    mv rtems-source-builder-6.2 rsb

# Build the RISC-V toolchain (gcc, gdb, dtc, rtems-tools)
RUN cd /opt/rtems/src/rsb/ && \
    python ./source-builder/sb-set-builder --prefix=/opt/rtems/6 6/rtems-riscv

# Set environment variable for RTEMS prefix
ENV PREFIX="/opt/rtems/6"

# RTEMS 6.2 kernel source (same release as the RSB). The BSP is configured
# and built by scripts/post_configuration.sh with /workspace/rtems/config.ini.
ARG RTEMS_SHA512=d48ba9542bd96cd7e0d480681bf99df652337ae31d73651882624e24e28931b4316a5ed00ec586d18f19490b8c859d7e87822333b81e0f6bd7e298f4c3e94f1e
RUN cd /opt/rtems/src && \
    wget -q https://ftp.rtems.org/pub/rtems/releases/6/6.2/sources/rtems-6.2.tar.xz && \
    echo "${RTEMS_SHA512}  rtems-6.2.tar.xz" | sha512sum -c - && \
    tar xJf rtems-6.2.tar.xz && \
    rm rtems-6.2.tar.xz && \
    mv rtems-6.2 rtems

# pkg-config for rtems-cmake (reads the BSP's .pc file). Installed here
# rather than in apt-packages.txt so the toolchain layer stays cached.
RUN sudo apt-get update && \
    sudo apt-get install -y pkg-config && \
    sudo rm -rf /var/lib/apt/lists/*

# HSS (Hart Software Services) source, built by /workspace/hss/build_hss.sh,
# and the HSS payload generator, which wraps the RTEMS ELF into an HSS boot
# image
ARG HSS_VERSION=v2026.04.1
ENV HSS_SRC="/opt/hss"
RUN sudo mkdir -p ${HSS_SRC} && \
    sudo chown ubuntu:ubuntu ${HSS_SRC} && \
    git clone --depth 1 --branch ${HSS_VERSION} https://github.com/polarfire-soc/hart-software-services.git ${HSS_SRC} && \
    make -C ${HSS_SRC}/tools/hss-payload-generator && \
    sudo install -m 755 ${HSS_SRC}/tools/hss-payload-generator/hss-payload-generator /usr/local/bin/ && \
    make -C ${HSS_SRC}/tools/hss-payload-generator clean

# xPack GNU RISC-V Embedded GCC, the toolchain the HSS expects
ARG XPACK_VERSION=15.2.0-1
ARG XPACK_SHA256=aaaa8060c914851a3e5ee1ba82cc3d6f80972f90638a05c6e823a37557a33758
RUN cd /tmp && \
    wget -q https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v${XPACK_VERSION}/xpack-riscv-none-elf-gcc-${XPACK_VERSION}-linux-x64.tar.gz && \
    echo "${XPACK_SHA256}  xpack-riscv-none-elf-gcc-${XPACK_VERSION}-linux-x64.tar.gz" | sha256sum -c - && \
    sudo tar xzf xpack-riscv-none-elf-gcc-${XPACK_VERSION}-linux-x64.tar.gz -C /opt && \
    rm xpack-riscv-none-elf-gcc-${XPACK_VERSION}-linux-x64.tar.gz
ENV PATH="$PATH:/opt/xpack-riscv-none-elf-gcc-${XPACK_VERSION}/bin"

# Default command
CMD ["/bin/bash"]
