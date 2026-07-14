# Start from the official Gentoo stage3 image
FROM gentoo/stage3:latest

# Sync the ebuild repository
RUN emerge --sync

# Install Catalyst and necessary system tool dependencies
RUN mkdir -p /etc/portage/package.accept_keywords && \
    printf 'dev-util/catalyst ~amd64\n' >/etc/portage/package.accept_keywords/catalyst && \
    mkdir -p /etc/portage/package.use && \
    printf 'dev-util/catalyst -iso -qcow2\nsys-apps/util-linux python\n' >/etc/portage/package.use/catalyst && \
    emerge dev-util/catalyst app-cdr/cdrtools

# Create the standard catalyst directory layout structure
RUN mkdir -p /var/tmp/catalyst/builds/default \
             /var/tmp/catalyst/config/stages \
             /etc/catalyst

# Copy default configuration templates into place
RUN test -f /etc/catalyst/catalyst.conf

WORKDIR /var/tmp/catalyst
