FROM debian:stable-slim as glibc-base

ARG GLIBC_VERSION=2.28
ARG GLIBC_PREFIX=/usr/glibc
ARG LANG=en_US.UTF-8

RUN apt-get update && apt-get install -y \
  curl build-essential gawk bison python3 texinfo gettext \
  && \
  cd /root && \
  curl -SL http://ftp.gnu.org/gnu/glibc/glibc-${GLIBC_VERSION}.tar.gz | tar xzf - && \
  mkdir -p /root/build && cd /root/build && \
  ../glibc-${GLIBC_VERSION}/configure \
    --prefix=${GLIBC_PREFIX} \
    --libdir="${GLIBC_PREFIX}/lib" \
    --libexecdir="${GLIBC_PREFIX}/lib" \
    --enable-multi-arch \
    --enable-stack-protector=strong \
  && \
  make -j`nproc` && make DESTDIR=/root/dest install && \
  LIBERICA_ARCH=`uname -m` && \
  if [ "$LIBERICA_ARCH" = "ppc64le" ]; then \
  RTLD=`find /root/dest${GLIBC_PREFIX}/lib -name 'ld64*.so.*'` && [ -x "$RTLD" ]; else  \
  RTLD=`find /root/dest${GLIBC_PREFIX}/lib -name 'ld-linux-*.so.*'` && [ -x "$RTLD" ]; fi && \
  LOCALEDEF="$RTLD --library-path /root/dest${GLIBC_PREFIX}/lib /root/dest${GLIBC_PREFIX}/bin/localedef --alias-file=/root/glibc-${GLIBC_VERSION}/intl/locale.alias" && \
  export I18NPATH=/root/glibc-${GLIBC_VERSION}/localedata && \
  export GCONVPATH=/root/glibc-${GLIBC_VERSION}/iconvdata && \
  LOCALE=$(echo ${LANG} | cut -d. -f1) && CHARMAP=$(echo ${LANG} | cut -d. -f2) && \
  mkdir -pv /root/dest${GLIBC_PREFIX}/lib/locale && \
  cd /root/glibc-${GLIBC_VERSION}/localedata && \
  ${LOCALEDEF} -i locales/$LOCALE -f charmaps/$CHARMAP --prefix=/root/dest $LANG && \
  cd /root && rm -rf build glibc-${GLIBC_VERSION} && \
  cd /root/dest${GLIBC_PREFIX} && \
  ( strip bin/* sbin/* lib/* || true ) && \
  echo "/usr/local/lib" > /root/dest${GLIBC_PREFIX}/etc/ld.so.conf && \
  echo "${GLIBC_PREFIX}/lib" >> /root/dest${GLIBC_PREFIX}/etc/ld.so.conf && \
  echo "/usr/lib" >> /root/dest${GLIBC_PREFIX}/etc/ld.so.conf && \
  echo "/lib" >> /root/dest${GLIBC_PREFIX}/etc/ld.so.conf


RUN cd /root/dest${GLIBC_PREFIX} && \
  rm -rf etc/rpc var include share bin sbin/[^l]*  \
	lib/*.o lib/*.a lib/audit lib/gconv lib/getconf

RUN LIBERICA_ARCH=`uname -m` && \
    if [ "$LIBERICA_ARCH" = "ppc64le" ]; then \
    apt-get install -yq zlib1g-dev gcc-8 libstdc++6 libgcc-8-dev && \
    cd / && \
    cd /usr/lib/powerpc64le-linux-gnu && \
    LNAME=`find . -name "libstdc++.so*" -type f | awk {'print $1'}` && \
    ln -s `basename ${LNAME}` libstdc++.so && \
    cd / && \
    tar chf /tmp/glibs.tar usr/lib/gcc/powerpc64le-linux-gnu/8/libgcc*so* && \
    tar rf /tmp/glibs.tar usr/lib/powerpc64le-linux-gnu/libstdc++* && \
    gzip /tmp/glibs.tar && \
    tar czf /tmp/libz.tar.gz lib/powerpc64le-linux-gnu/libz* ; fi

#sbin/[^l]*

FROM alpine:3.11 as liberica

ARG GLIBC_PREFIX=/usr/glibc
ARG EXT_GCC_LIBS_URL=https://archive.archlinux.org/packages/g/gcc-libs/gcc-libs-8.3.0-1-x86_64.pkg.tar.xz
ARG EXT_ZLIB_URL=https://archive.archlinux.org/packages/z/zlib/zlib-1%3A1.2.11-3-x86_64.pkg.tar.xz
ARG LANG=en_US.UTF-8
ARG OPT_PKGS=

ENV  LANG=${LANG} \
     LANGUAGE=${LANG}:en
#	 LC_ALL=en_US.UTF-8

ARG LIBERICA_ROOT=/usr/lib/jvm/jdk-11.0.9-bellsoft
ARG LIBERICA_VERSION=11.0.9.1
ARG LIBERICA_BUILD=1
ARG LIBERICA_VARIANT=jdk
ARG LIBERICA_USE_LITE=0

COPY --from=glibc-base /root/dest/ /
COPY --from=glibc-base /tmp/glibs.tar.gz /tmp/glibs.tgz
COPY --from=glibc-base /tmp/libz.tar.gz  /tmp/libz.tgz

RUN LIBERICA_ARCH='' && LIBERICA_ARCH_TAG='' && \
  case `uname -m` in \
        x86_64) \
            LIBERICA_ARCH="amd64" \
            ;; \
        i686) \
            LIBERICA_ARCH="i586" \
            ;; \
        aarch64) \
            LIBERICA_ARCH="aarch64" \
            ;; \
        armv[67]l) \
            LIBERICA_ARCH="arm32-vfp-hflt"; \
            ;; \
        *) \
            LIBERICA_ARCH=`uname -m` \
            ;; \
  esac  && \
  ln -s ${GLIBC_PREFIX}/lib/ld-*.so* /lib && \
  ln -s ${GLIBC_PREFIX}/etc/ld.so.cache /etc && \
  if [ "$LIBERICA_ARCH" = "amd64" ]; then ln -s /lib /lib64 && \
  mkdir /tmp/zlib && wget -O - "${EXT_ZLIB_URL}" | tar xJf - -C /tmp/zlib && \
  cp -dP /tmp/zlib/usr/lib/libz.so* "${GLIBC_PREFIX}/lib" && \
  rm -rf /tmp/zlib && \
  mkdir /tmp/gcc && wget -O - "${EXT_GCC_LIBS_URL}" | tar xJf - -C /tmp/gcc && \
  cp -dP /tmp/gcc/usr/lib/libgcc* /tmp/gcc/usr/lib/libstdc++* "${GLIBC_PREFIX}/lib" && \
  rm -rf /tmp/gcc; fi && \
  if [ "$LIBERICA_ARCH" = "ppc64le" ]; then ln -s /lib /lib64 && \
  mkdir /tmp/zlib && tar xzf /tmp/libz.tgz -C /tmp/zlib && \
    cp -dP /tmp/zlib/lib/powerpc64le-linux-gnu/libz.so* "${GLIBC_PREFIX}/lib" && \
  mkdir /tmp/gcc && tar xzf /tmp/glibs.tgz -C /tmp/gcc && \
    cp -dP /tmp/gcc/usr/lib/gcc/powerpc64le-linux-gnu/8/libgcc* \
           /tmp/gcc/usr/lib/powerpc64le-linux-gnu/libstdc++* "${GLIBC_PREFIX}/lib" && \
  rm -rf /tmp/glibs.tgz /tmp/libz.tgz /tmp/zlib /tmp/gcc; fi && \
  for pkg in $OPT_PKGS ; do apk --no-cache add $pkg ; done && \
  ${GLIBC_PREFIX}/sbin/ldconfig && \
  echo 'hosts: files mdns4_minimal [NOTFOUND=return] dns mdns4' > /etc/nsswitch.conf && \
  mkdir -p $LIBERICA_ROOT && \
  mkdir -p /tmp/java && \
  RSUFFIX="" && if [ "$LIBERICA_USE_LITE" = "1" ]; then RSUFFIX="-lite"; fi && \
  LIBERICA_BUILD_STR=${LIBERICA_BUILD:+"+${LIBERICA_BUILD}"} && \
  PKG=`echo "bellsoft-${LIBERICA_VARIANT}${LIBERICA_VERSION}${LIBERICA_BUILD_STR}-linux-${LIBERICA_ARCH}${RSUFFIX}.tar.gz"` && \
  wget "https://download.bell-sw.com/java/${LIBERICA_VERSION}${LIBERICA_BUILD_STR}/${PKG}" -O /tmp/java/jdk.tar.gz && \
  SHA1=`wget -q "https://download.bell-sw.com/sha1sum/java/${LIBERICA_VERSION}${LIBERICA_BUILD_STR}" -O - | grep ${PKG} | cut -f1 -d' '` && \
  echo "${SHA1} */tmp/java/jdk.tar.gz" | sha1sum -c - && \
  tar xzf /tmp/java/jdk.tar.gz -C /tmp/java && \
  find "/tmp/java/${LIBERICA_VARIANT}-${LIBERICA_VERSION}${RSUFFIX}" -maxdepth 1 -mindepth 1 -exec mv "{}" "${LIBERICA_ROOT}/" \; && \
  ln -s "${LIBERICA_ROOT}" /usr/lib/jvm/jdk && \
  rm -rf /tmp/java

ENV JAVA_HOME=${LIBERICA_ROOT} \
	PATH=${LIBERICA_ROOT}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
