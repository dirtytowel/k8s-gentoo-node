# Start from the official Gentoo stage3 image
FROM gentoo/stage3:latest
RUN emerge --sync

# install catalyst
RUN rm -rf /etc/portage/package.accept_keywords && \
    echo 'dev-util/catalyst ~amd64' >> /etc/portage/package.accept_keywords; \
    rm -rf /etc/portage/package.use && \
    echo 'dev-util/catalyst -iso -qcow2' >> /etc/portage/package.use; \
    echo 'sys-apps/util-linux python' >> /etc/portage/package.use; \
    emerge dev-util/catalyst app-cdr/cdrtools

# catalyst dirs
RUN mkdir -p /var/tmp/catalyst/builds/default \
             /var/tmp/catalyst/config/stages \
             /var/tmp/catalyst/repos \
             /var/tmp/catalyst/snapshots \
             /etc/catalyst

RUN echo 'export MAKEOPTS="-j$(nproc) -l$(nproc)"' >> /etc/catalyst/catalystrc; \
    echo 'export NICENESS="19"' >> /etc/catalyst/catalystrc

WORKDIR /var/tmp/catalyst
