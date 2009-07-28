#
# Makefile to generate DEB, RPM and TGZ for vzdump
#
# possible targets:
#
# all:          create DEB, RPM and TGZ packages
# clean:        cleanup
# deb:          create debian package
# rpm:	        create rpm package
# srpm:	        create src.rpm package
# dist:         create tgz package
# install:      install files

VERSION=1.1
PACKAGE=vzdump
PKGREL=2

DESTDIR=
PREFIX=/usr
SBINDIR=${PREFIX}/sbin
MANDIR=${PREFIX}/share/man
DOCDIR=${PREFIX}/share/doc
MAN1DIR=${MANDIR}/man1/

DEB=${PACKAGE}_${VERSION}-${PKGREL}_all.deb
RPM=${PACKAGE}-${VERSION}-${PKGREL}.noarch.rpm
SRPM=${PACKAGE}-${VERSION}-${PKGREL}.src.rpm
DISTDIR=$(PACKAGE)-$(VERSION)
TGZ=${DISTDIR}.tar.gz

RPMSRCDIR=$(shell rpm --eval %_sourcedir)
RPMDIR=$(shell rpm --eval %_rpmdir)
SRPMDIR=$(shell rpm --eval %_srcrpmdir)

DISTFILES=			\
	ChangeLog 		\
	TODO			\
	Makefile  		\
	changelog.Debian  	\
	control.in  		\
	vzdump.spec.in		\
	copyright  		\
	vzdump

all: ${TGZ} ${DEB} ${RPM}

control: control.in
	sed -e s/@@VERSION@@/${VERSION}/ -e s/@@PKGRELEASE@@/${PKGREL}/ <$< >$@

vzdump.spec: vzdump.spec.in
	sed -e s/@@VERSION@@/${VERSION}/ -e s/@@PKGRELEASE@@/${PKGREL}/ <$< >$@

.PHONY: install
install: vzdump vzdump.1
	install -d ${DESTDIR}${SBINDIR}
	install -m 0755 vzdump ${DESTDIR}${SBINDIR}
	install -d ${DESTDIR}${MAN1DIR}
	install -m 0644 vzdump.1 ${DESTDIR}${MAN1DIR}
	gzip -f9 ${DESTDIR}${MAN1DIR}/vzdump.1

.PHONY: deb
deb ${DEB}: vzdump.1 control ${DISTFILES}
	rm -rf debian
	mkdir debian
	make DESTDIR=debian install
	install -d -m 0755 debian/DEBIAN
	install -m 0644 control debian/DEBIAN
	install -D -m 0644 copyright debian/${DOCDIR}/${PACKAGE}/copyright
	install -m 0644 changelog.Debian debian/${DOCDIR}/${PACKAGE}/
	install -m 0644 ChangeLog debian/${DOCDIR}/${PACKAGE}/changelog
	gzip -9 debian/${DOCDIR}/${PACKAGE}/changelog.Debian
	gzip -9 debian/${DOCDIR}/${PACKAGE}/changelog
	dpkg-deb --build debian	
	mv debian.deb ${DEB}
	rm -rf debian
	lintian ${DEB}

vzdump.1: vzdump
	rm -f vzdump.1
	pod2man -n $< -s 1 -r ${VERSION} <$< >$@

.PHONY: rpm
rpm ${RPM}: ${TGZ} ${PACKAGE}.spec
	cp ${TGZ} ${RPMSRCDIR}
	rpmbuild -bb --nodeps --clean --rmsource ${PACKAGE}.spec
	mv ${RPMDIR}/noarch/${RPM} ${RPM} 

.PHONY: srpm
srpm ${SRPM}: ${TGZ} ${PACKAGE}.spec
	cp ${TGZ} ${RPMSRCDIR}
	rpmbuild -bs --nodeps --rmsource ${PACKAGE}.spec
	mv ${SRPMDIR}/${SRPM} ${SRPM} 


.PHONY: dist
dist: ${TGZ}

${TGZ}: ${DISTFILES}
	make clean
	rm -rf ${TGZ} ${DISTDIR}
	mkdir ${DISTDIR}
	cp ${DISTFILES} ${DISTDIR}
	tar czvf ${TGZ} ${DISTDIR}
	rm -rf ${DISTDIR} 

.PHONY: clean
clean: 	
	rm -rf debian *~ *.deb *.tar.gz *.rpm vzdump.1 vzdump.spec control ${DISTDIR}