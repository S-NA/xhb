
. version.sh
export XPROTO_VERSION

XPROTO_PACKAGE=xcb-proto-${XPROTO_VERSION}

DOWNLOAD_PATH=resources
XML_TARBALL=http://xcb.freedesktop.org/dist/${XPROTO_PACKAGE}.tar.gz
XML_DIR=${DOWNLOAD_PATH}/${XPROTO_PACKAGE}/src
XML_FILES=*.xml

GENERAL_ERROR=1

#include the xproto version in the output-dir
OUT_DIR=${OUT_DIR}/${XPROTO_VERSION}

UTIL_PATH=build-utils/dist/build
PROG=${UTIL_PATH}/${TEST_PROG}/${TEST_PROG}

#Do we have the test program?
[ -f ${PROG} ] || {
    pushd build-utils > /dev/null

    [ -f cabal.sandbox.config ] || {
        cabal sandbox init
        cabal install -j --dependencies-only
    }
    cabal configure
    cabal build

    popd > /dev/null
}
[ -f ${PROG} ] || {
    echo "Unable to build ${PROG}"
    exit ${GENERAL_ERROR}
}


#Do the XML files exist?
[ -d ${XML_DIR} ] || {

    [ $(which curl) ]  || {
	echo "Cannot find 'curl' in path"
	exit ${GENERAL_ERROR}
    }

    [ -d ${DOWNLOAD_PATH} ] || {
        #attempt to create the directory
	mkdir -p ${DOWNLOAD_PATH}
    }

    [ -d ${DOWNLOAD_PATH} ] || {
	#didn't create directory :-(
	echo "couldn't create directory ${DOWNLOAD_PATH}"
	exit ${GENERAL_ERROR}
    }

    curl ${XML_TARBALL} | tar -xzC ${DOWNLOAD_PATH}
}

[ -d ${XML_DIR} ] || {
    echo "Soething went wrong, I can't find ${XML_DIR}"
    exit ${GENERAL_ERROR}
}

#Cleanup after prvious run
if [ -d ${OUT_DIR} ]; then
    rm -rf ${OUT_DIR}
fi
mkdir -p ${OUT_DIR}


#Go!
${PROG} ${OUT_DIR} ${XML_DIR}/${XML_FILES} || {
    echo "failed!"
    exit ${GENERAL_ERROR}
}
