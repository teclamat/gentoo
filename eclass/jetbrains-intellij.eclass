# Copyright 2016-2018 Jan Chren (rindeal)
# Distributed under the terms of the GNU General Public License v2

# @ECLASS: jetbrains-intellij.eclass
# @MAINTAINER: Jan Chren (rindeal) <dev.rindeal+gentoo-overlay@gmail.com>
# @BLURB: Boilerplate for IntelliJ based IDEs
# @DESCRIPTION:

if [ -z "${_JETBRAINS_INTELLIJ_ECLASS}" ] ; then

case "${EAPI:-0}" in
	6) ;;
	*) die "Unsupported EAPI='${EAPI}' for '${ECLASS}'" ;;
esac

### BEGIN: standard tool wrappers

# `NO_V` env var implementation for use in standard tool wrappers
_NO_V() {
	echo "$( (( NO_V )) || echo '--verbose' )"
}

rpushd() {
	pushd "${@}" >/dev/null || die -n
}

rpopd() {
	popd "${@}" >/dev/null || die -n
}

rmkdir() {
	mkdir $(_NO_V) -p "${@}" || die -n
}

rcp() {
	cp $(_NO_V) "${@}" || die -n
}

rmv() {
	mv $(_NO_V) "${@}" || die -n
}

rln() {
	ln $(_NO_V) "${@}" || die -n
}

rchown() {
	chown $(_NO_V) "${@}" || die -n
}

rchmod() {
	chmod $(_NO_V) "${@}" || die -n
}

rrm() {
	rm $(_NO_V) --interactive=never --preserve-root --one-file-system "${@}" || die -n
}

rrmdir() {
	rmdir $(_NO_V) "${@}" || die -n
}

rsed() {
	local diff_prog=()

	if (( RINDEAL_DEBUG )) ; then
		diff_prog=( diff -u )
		if command -v colordiff >/dev/null ; then
			diff_prog=( colordiff -u )
		fi

		local -A file_list
		local pretty_sed=()
		local i record_files=0
		for (( i=1 ; i <= $# ; i++ )) ; do
			local arg="${!i}"
			if (( record_files )) ; then
				file_list+=( ["${arg}"]="${RANDOM}${RANDOM}${RANDOM}" )
			else
				if [[ "${arg}" == "--" ]] ; then
					record_files=1
				else
					pretty_sed+=( "'${arg}'" )
				fi
			fi
		done

		(( ${#file_list[*]} )) || die -n

		local temp_dir="$(mktemp -d)" || die -n

		## backup original versions
		local f
		for f in "${!file_list[@]}" ; do
			cp -- "${f}" "${temp_dir}/${file_list["${f}"]}" || die -n
		done
	fi

	sed "${@}" || die -n

	if (( ${#diff_prog[*]} )) ; then
		local f
		for f in "${!file_list[@]}" ; do
			echo "*** diff of '${f}'"
			echo "*** for sed ${pretty_sed[*]}:"
			"${diff_prog[@]}" "${temp_dir}/${file_list["${f}"]}" "${f}"
			local code=$?
			(( code == 2 )) && die -n
			(( code == 0 )) && eqawarn "sed didn't change anything"
		done
		rm -r -- "${temp_dir}" || die -n
	fi
}

### END: standard tool wrappers

## functions: get_version_component_range, get_major_version
inherit versionator

## EXPORT_FUNCTIONS: src_prepare, pkg_preinst, pkg_postinst, pkg_postrm
inherit xdg

## functions: make_desktop_entry, newicon
inherit desktop

## functions: eshopts_push, eshopts_pop
inherit estack


declare -g -r \
	_JBIJ_PN_BASE="${PN%"-community"}"

HOMEPAGE="https://www.jetbrains.com/${_JBIJ_PN_BASE}"
LICENSE="IDEA || ( IDEA_Academic IDEA_Classroom IDEA_OpenSource IDEA_Personal )"

SLOT="$(get_version_component_range 1-2)"
declare -g -r \
	_JBIJ_PN_SLOTTED="${PN}${SLOT}"

# @ECLASS-VARIABLE: JBIJ_URI
# @DEFAULT:
# 	JBIJ_URI="${PN}/${P}"
# @DESCRIPTION:
# 	The part of SRC_URI between domain name and extension.
# 	This varies greatly among packages as the first part is usually an internal codename of the product.
: "${JBIJ_URI:="${PN}/${P}"}"
readonly JBIJ_URI

SRC_URI="https://download.jetbrains.com/${JBIJ_URI}.tar.gz"

KEYWORDS="~amd64"
IUSE="system-jre"
RESTRICT+=" mirror strip test"

RDEPEND="system-jre? ( >=virtual/jre-1.8 )"


# @ECLASS-VARIABLE: JBIJ_TAR_EXCLUDE
# @DESCRIPTION:
# 	An array of paths relative to the ${S} dir, which will be excluded when unpacking the archive.
# 	Please put here only files/dirs with big size or many inodes.
declare -g -r \
	_JBIJ_DEFAULT_TAR_EXCLUDE=(
		'license'
		# This plugin has several QA violations, eg. https://github.com/rindeal/gentoo-overlay/issues/67.
		# If someone needs it, it can be installed separately from JetBrains plugin repo.
		'plugins/tfsIntegration'
		## arm
		'bin/fsnotifier-arm'
		## x86
		bin/{fsnotifier,libbreakgen.so,libyjpagent-linux.so}
	)

# @ECLASS-VARIABLE: JBIJ_PN_PRETTY
# @DESCRIPTION:
# 	Prettified PN.
# 	This will be used in various user-facing places, eg. the desktop menu entry.
: "${JBIJ_PN_PRETTY:="${PN^}"}"
readonly JBIJ_PN_PRETTY


EXPORT_FUNCTIONS src_unpack src_prepare src_compile pkg_preinst src_install pkg_postinst pkg_postrm


jetbrains-intellij_src_unpack() {
	debug-print-function ${FUNCNAME}

	## pick the first archive from SRC_URI
	local _A=( $A )
	# if you'll ever need >1 archive, put a special override variable for the following check,
	# do not throw it away completely
	(( ${#_A[@]} == 1 )) || die "Your SRC_URI contains too many archives"
	local -r archive="${DISTDIR}/${_A[0]}"

	einfo "Unpacking '${archive}' to '${S}'"

	NO_V=1 rmkdir "${S}"

	local tar=(
		tar --extract

		--no-same-owner --no-same-permissions
		--strip-components=1 # otherwise we'd have to specify excludes as `${P}/path`

		--file="${archive}"
		--directory="${S}"
	)

	local excludes=( "${_JBIJ_DEFAULT_TAR_EXCLUDE[@]}" )
	use system-jre && excludes+=( 'jre' )
	use amd64      || excludes+=( bin/{fsnotifier64,libbreakgen64.so,libyjpagent-linux64.so,LLDBFrontend} )

	readonly JBIJ_TAR_EXCLUDE
	excludes+=( "${JBIJ_TAR_EXCLUDE[@]}" )

	einfo "Excluding: $(printf "'%s' " "${excludes[@]}")"
	tar+=( "${excludes[@]/#/--exclude=}" )

	debug-print "${FUNCNAME}: $(printf "'%s' " "${tar[@]}")'"
	"${tar[@]}" || die
}


jetbrains-intellij_src_prepare() {
	debug-print-function "${FUNCNAME}" "${@}"

	xdg_src_prepare
}


jetbrains-intellij_src_compile() { : ; }


# ### BEGIN ### Install ###

# @ECLASS-VARIABLE: JBIJ_DESKTOP_CATEGORIES=()
# @DEFAULT_UNSET
# @DESCRIPTION:
# 	An array of additional desktop menu entry categories.
# 	Defaults are 'Development;IDE;Java', which cannot be unset.
declare -g -r \
	_JBIJ_DEFAULT_DESKTOP_CATEGORIES=(
		'Development'
		'IDE'
		'Java'
	)

# @ECLASS-VARIABLE: JBIJ_DESKTOP_EXTRAS=()
# @DEFAULT_UNSET
# @DESCRIPTION:
# 	An array of lines which will be appended to the generated '.desktop' file.
declare -g -r \
	_JBIJ_DEFAULT_DESKTOP_EXTRAS=(
		"StartupWMClass=jetbrains-${PN}"
	)

# @ECLASS-VARIABLE: JBIJ_INSTALL_DIR
# @DESCRIPTION:
# 	Readonly variable pointing to the directory under which everything will be installed.
# 	The path is without EPREFIX.
declare -g -r \
	JBIJ_INSTALL_DIR="/opt/jetbrains/${_JBIJ_PN_SLOTTED}"

# @ECLASS-VARIABLE: JBIJ_STARTUP_SCRIPT_NAME
# @DESCRIPTION:
# 	Filename of the startup script.
# 	This file must be located in the 'bin/' dir and ends with '.sh'.
: "${JBIJ_STARTUP_SCRIPT_NAME:="${_JBIJ_PN_BASE}.sh"}"
readonly JBIJ_STARTUP_SCRIPT_NAME

_jetbrains-intellij_src_install-icon() {
	debug-print-function "${FUNCNAME}" "${@}"

	# First find any '*.svg' and '*.png' images in the 'bin/' dir.
	# Nullglob is required otherwise BASH will think '*' is a filename.
	eshopts_push -s nullglob
	local -r svg=( bin/*.svg ) png=( bin/*.png )
	eshopts_pop

	# prefer SVG icons if any were found
	if (( ${#svg[@]} )) ; then
		newicon -s scalable "${svg[0]}" "${_JBIJ_PN_SLOTTED}.svg"

	# PNG otherwise
	elif (( ${#png[@]} )) ; then
		# icons size is sometimes 128 and sometimes 256, let's stick with the smaller value
		newicon -s 128 "${png[0]}" "${_JBIJ_PN_SLOTTED}.png"

	# throw ebuild QA warning if nothing was found
	else
		equawarn "No icon found"
	fi
}

_jetbrains-intellij_src_install-pre() {
	debug-print-function "${FUNCNAME}" "${@}"

	_jetbrains-intellij_src_install-icon
}

_jetbrains-intellij_src_install-fix() {
	debug-print-function "${FUNCNAME}" "${@}"

	## first check the directory has a structure that we expect it to have
	[[ -f "bin/${JBIJ_STARTUP_SCRIPT_NAME}" ]] || die "'bin/${JBIJ_STARTUP_SCRIPT_NAME}' not found"

	## fix permissions
	rchmod a+x bin/${JBIJ_STARTUP_SCRIPT_NAME}
	rchmod a+x bin/fsnotifier*

	if ! use system-jre ; then
		# upstream renames/moves this dir very often
		# https://github.com/rindeal/gentoo-overlay/issues/160
		# https://github.com/rindeal/gentoo-overlay/issues/165
		eshopts_push -s globstar
		rchmod a+x **/jre*/**/bin/*
		eshopts_pop
	fi

	if [[ -v JBIJ_ADDITIONAL_EXECUTABLES[@] ]] ; then
		rchmod a+x "${JBIJ_ADDITIONAL_EXECUTABLES[@]}"
	fi
}

_jetbrains-intellij_src_install-post() {
	debug-print-function "${FUNCNAME}" "${@}"

    ## install symlink for the launcher
	dosym "${JBIJ_INSTALL_DIR}/bin/${JBIJ_STARTUP_SCRIPT_NAME}" "/usr/bin/${_JBIJ_PN_SLOTTED}"

	## generate and install .desktop menu file
	local -r make_desktop_entry_args=(
		# start the script directly
		"${_JBIJ_PN_SLOTTED} %U"    # exec
		"${JBIJ_PN_PRETTY} ${SLOT}" # name
		"${_JBIJ_PN_SLOTTED}"       # icon
		"$(printf '%s;' "${_JBIJ_DEFAULT_DESKTOP_CATEGORIES[@]}" "${JBIJ_DESKTOP_CATEGORIES[@]}")"  # categories
	)
	local -r make_desktop_entry_extras=(
		"${_JBIJ_DEFAULT_DESKTOP_EXTRAS[@]}"
		"${JBIJ_DESKTOP_EXTRAS[@]}"
	)
	make_desktop_entry "${make_desktop_entry_args[@]}" \
		"$( printf '%s\n' "${make_desktop_entry_extras[@]}" )"

	## recommended by: https://confluence.jetbrains.com/display/IDEADEV/Inotify+Watches+Limit
	NO_V=1 rmkdir "${D}"/etc/sysctl.d
	echo "fs.inotify.max_user_watches = 524288" \
		>"${D}"/etc/sysctl.d/30-idea-inotify-watches.conf || die
}

jetbrains-intellij_src_install() {
	debug-print-function "${FUNCNAME}" "${@}"

	_jetbrains-intellij_src_install-pre

	rmkdir "${ED%/}${JBIJ_INSTALL_DIR}"

	# use `cp` as `doins()` is too slow
	NO_V=1 rcp -r . "${ED%/}${JBIJ_INSTALL_DIR}"

	# normalize permissions as `install` would
	find "${ED%/}${JBIJ_INSTALL_DIR}" -type f -print0 | xargs -0 chmod 644 --
	assert

	## now let's push into the image dir and change few things in there
	rpushd "${ED%/}${JBIJ_INSTALL_DIR}"
	_jetbrains-intellij_src_install-fix
	rpopd

	_jetbrains-intellij_src_install-post
}

# ### END ### Install ###


jetbrains-intellij_pkg_preinst() {
	debug-print-function "${FUNCNAME}" "${@}"
	xdg_pkg_preinst
}


jetbrains-intellij_pkg_postinst() {
	debug-print-function "${FUNCNAME}" "${@}"
	xdg_pkg_postinst
}


jetbrains-intellij_pkg_postrm() {
	debug-print-function "${FUNCNAME}" "${@}"
	xdg_pkg_postrm
}


_JETBRAINS_INTELLIJ_ECLASS=1
fi

