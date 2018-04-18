#!/bin/bash

DEBIAN_EDITION="stable"
DEBIAN_ROOT="debian_root"
DEBIAN_PATH="/home/linaro/${DEBIAN_ROOT}"
DEBIAN_MIRROR="http://mirror.yandex.ru/debian"

PROCESS_COUNT_FILE="/dev/shm/${DEBIAN_ROOT}.lock"

function change_proc_count() {
	local counter=0
	if [ -f ${PROCESS_COUNT_FILE} ];then
		counter=$(flock -x -w 10 ${PROCESS_COUNT_FILE} -c "cat ${PROCESS_COUNT_FILE}")
		if [ -z ${counter} ]; then
			counter=0
		fi
	fi
	{
		flock -x -w 10 3 || exit 1
		if [ $1 -eq 1 ]; then
			counter=$((counter + 1))
		else
			if [ counter != 0 ];then
				counter=$((counter - 1))
			fi
		fi
		echo $counter>&3
	} 3>${PROCESS_COUNT_FILE}
	if [ $counter -eq 0 ];then
		rm -f ${PROCESS_COUNT_FILE}
	fi
	echo $counter
}

function request_root() {
	if [ $EUID != 0 ]; then
		sudo "$0" "$@"
		exit $?
	fi
}

function clean_garbage() {
	rm -rf "${DEBIAN_PATH}/tmp/*"
}

function mount_points() {
	local DEBIAN_PROC="${DEBIAN_PATH}/proc"
	local DEBIAN_SYS="${DEBIAN_PATH}/sys"
	local DEBIAN_DEV="${DEBIAN_PATH}/dev"
	
	if [ $1 -eq 1 ]; then
		if ! mountpoint -q ${DEBIAN_PROC}; then
			mount -t proc /proc ${DEBIAN_PROC}
		fi
		if ! mountpoint -q ${DEBIAN_SYS}; then
			mount --rbind /sys ${DEBIAN_SYS}
			mount --make-rslave ${DEBIAN_SYS}
		fi
		if ! mountpoint -q ${DEBIAN_DEV}; then
			mount --rbind /dev ${DEBIAN_DEV}
			mount --make-rslave ${DEBIAN_DEV}
		fi
	else
		umount -R ${DEBIAN_DEV}
		umount -R ${DEBIAN_SYS}
		umount ${DEBIAN_PROC}
		clean_garbage
	fi
}

function run_chrooted_process() {
	chroot ${DEBIAN_PATH} /usr/bin/env -i \
		HOME=/root \
		TERM=$TERM \
		PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games" \
		PS1='\u:\w\$ ' \
		/bin/bash -c "source /etc/environment && source /etc/profile && $1" --login +h
}

function update_apt_list() {
	local APT_PATH="${DEBIAN_PATH}/etc/apt"
	if [ ! -d ${APT_PATH} ]; then
		echo "Creating apt path"
		mkdir -p ${APT_PATH}
	fi

	echo "Create new apt list file"
	local APT_LIST_PATH="${APT_PATH}/sources.list"

	local BIN_TEMP="deb ${DEBIAN_MIRROR} ${DEBIAN_EDITION}"
	local SRC_TEMP="deb-src ${DEBIAN_MIRROR} ${DEBIAN_EDITION}"
	local REPOS="main contrib non-free"

	echo "${BIN_TEMP} ${REPOS}" > $APT_LIST_PATH
	echo "${BIN_TEMP}-updates ${REPOS}" >> $APT_LIST_PATH
	echo "${SRC_TEMP} ${REPOS}" >> $APT_LIST_PATH		
	echo "${SRC_TEMP}-updates ${REPOS}" >> $APT_LIST_PATH

	run_chrooted_process "apt-get update && apt-get -y install dialog apt-utils && apt-get -y upgrade"
}

function install_locale() {
	run_chrooted_process "apt-get -y install locales"
	sed -i 's/^# *\(en_US.UTF-8\)/\1/' ${DEBIAN_PATH}/etc/locale.gen
	run_chrooted_process "locale-gen"
}

function make_install() {
	echo "Installing Debian base system to chroot"
	debootstrap --variant=buildd --arch amd64 ${DEBIAN_EDITION} ${DEBIAN_PATH} ${DEBIAN_MIRROR}

	echo "Configuring target system"
	
	echo "Coping hosts file"
	cp -vp /etc/hosts ${DEBIAN_PATH}/etc/hosts

	echo "Setting chroot name"
	echo "debian" > ${DEBIAN_PATH}/etc/debian_chroot

	mount_points 1

	update_apt_list
	install_locale

	echo "Setup ccache"
	echo "max_size = 50.0G" > ${DEBIAN_PATH}/etc/ccache.conf
	echo "export PATH=\"/usr/lib/ccache/bin/:\$PATH\"" > ${DEBIAN_PATH}/etc/profile.d/ccache.sh
	chmod +x ${DEBIAN_PATH}/etc/profile.d/ccache.sh
	run_chrooted_process "apt-get -y install ccache"
}

request_root
change_proc_count 1 > /dev/null

# Make install if target root does not exists
if [ ! -d ${DEBIAN_PATH} ]; then
	mkdir ${DEBIAN_PATH}
	make_install
fi

mount_points 1
run_chrooted_process "/bin/bash"

if [ $(change_proc_count 0) -eq 0 ];then
	mount_points 0
fi
