# Copyright 1999-2017 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Id$

EAPI=6
inherit cmake-utils cmake-multilib versionator udev

DESCRIPTION="Open source cross-platform driver for Kinect for Windows v2 devices."
HOMEPAGE="https://github.com/OpenKinect/libfreenect2"

SRC_URI="https://github.com/OpenKinect/libfreenect2/archive/v${PV}.tar.gz"
KEYWORDS="~x86 ~amd64"

LICENSE="GPL-2"
SLOT="0"


IUSE="+opengl -vaapi -cuda -opencl +protonect -static-libs -doc"
# properly handle cuda - propertiary nvidia driver, detect nouveau and die etc
# properly handle opencl!! 

DEPEND="
    >=dev-libs/libusb-1.0.20[udev]
    media-libs/libjpeg-turbo
    opengl? ( virtual/opengl )
    opengl? ( >=media-libs/glfw-3.0.0 )
    vaapi? ( x11-libs/libva )
    doc? ( app-doc/doxygen )
"

# Add OpenNI2 support for amd64 only
if [ ${ARCH} == "amd64" ]; then
    IUSE="${IUSE} -openni2"
    DEPEND="
        ${DEPEND}
        openni2? ( dev-libs/OpenNI2 )
    "
fi

RDEPEND="
    virtual/udev
    vaapi? ( media-libs/mesa[vaapi] )
"

src_unpack()
{
    unpack ${A}
    if [ ${ARCH} == "amd64" ]; then
        cd "${S}"
        epatch "${FILESDIR}/lib64fix.patch"
    fi
    # Fix for version naming mismatch
    # local PVMINOR=$(get_after_major_version)
    # S="$WORKDIR/${PN}2-0.${PVMINOR}"
}

src_configure()
{
    local sharedlibs="-DBUILD_SHARED_LIBS=ON"
    if use static-libs ; then
        sharedlibs="-DBUILD_SHARED_LIBS=OFF"
    fi
    local mycmakeargs=(
        -DCMAKE_BUILD_WITH_INSTALL_RPATH=TRUE
        ${sharedlibs}
        -DBUILD_EXAMPLES=$(usex protonect)
        -DENABLE_CXX11=ON
        -DENABLE_OPENGL=$(usex opengl)
        -DENABLE_OPENCL=$(usex opencl)
        -DENABLE_CUDA=$(usex cuda)
        -DENABLE_VAAPI=$(usex vaapi)
        -DENABLE_TEGRAJPEG=OFF
        -DENABLE_PROFILING=OFF
    )

    cmake-utils_src_configure
}

src_compile()
{
    # CMAKE_VERBOSE="OFF"
    cmake-utils_src_compile

    if use doc ; then
        # By deafault project is generating html documentation only
        # we thus 'sed' Doxyfile to enable generating man pages too
        local doxyFile="${BUILD_DIR}/doc/Doxyfile"
        sed -ri "s/^(GENERATE_MAN.+)(NO)$/\1YES/" $doxyFile
        doxygen $doxyFile
    fi
}

src_install()
{
    cmake-utils_src_install

    # Additional headers not hadled by cmake install
    if use opengl ; then
        doheader ${S}/src/flextGL.h
    fi

    # Utils binaries
    if use protonect ; then
        dobin ${BUILD_DIR}/bin/Protonect
    fi
    
    # udev rule for kinect usb device
    insinto $(get_udevdir)/rules.d
    doins ${S}/platform/linux/udev/*
    elog "Please reconnect Kinect v2 devices"
    elog "for new udev rule to be applied"

    # Documentation
    if use doc ; then
        doman ${BUILD_DIR}/doc/man/man*/*
        dohtml -r ${BUILD_DIR}/doc/html/*
    fi
}
