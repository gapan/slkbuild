#Packager: Name <email@address.com>
#Former Packager(s): Name <email@address.com>
#Anything commented out is optional and can be deleted.

pkgname=
pkgver=
pkgrel=
#arch=noarch
source=()
#sourcetemplate=http://people.salixos.org/yournick/$pkgname/$pkgver/
#docs=("readme" "install" "copying" "changelog" "authors" "news" "todo")
#url=
#dotnew=()
#CFLAGS=
#CXXFLAGS=
#options=('noextract')

#doinst() {
#
#}

slackdesc=\
(
#|-----handy-ruler------------------------------------------------------|
""
)


build() {
	cd $startdir/src/$pkgname-$pkgver

	mkdir -p build
	cd build

	# Your application will probably need different cmake flags; these are only
	# examples. You might want to run 'ccmake' inside the source main directory
	# to see available flags.
	cmake \
		-DCMAKE_C_FLAGS:STRING="$CFLAGS" \
		-DCMAKE_CXX_FLAGS:STRING="$CXXFLAGS" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DLIB_SUFFIX=${LIBDIRSUFFIX} \
		-DMAN_INSTALL_DIR=/usr/man \
		-DCMAKE_BUILD_TYPE=Release \
		..
	make -j $numjobs || return 1
	make install DESTDIR=$startdir/pkg

	cd ..
} 
