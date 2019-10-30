repo --name="AppStream" --baseurl=http://mirror.centos.org/centos/8/AppStream/x86_64/os/
repo --name="BaseOS" --baseurl=http://mirror.centos.org/centos/8/BaseOS/x86_64/os/
repo --name="PowerTools" --baseurl=http://mirror.centos.org/centos/8/PowerTools/x86_64/os/
repo --name="extras" --baseurl=http://mirror.centos.org/centos/8/extras/x86_64/os/
repo --name="epel" --baseurl=https://mirror.atl.genesisadaptive.com/epel//8/Everything/x86_64/
repo --name="ManageIQ-Build" --baseurl=https://copr-be.cloud.fedoraproject.org/results/manageiq/ManageIQ-Build/epel-8-x86_64/

cdrom
firstboot --disable
logging --level=debug

lang en_US.UTF-8
keyboard us
rootpw  --iscrypted $1$DZprqvCu$mhqFBjfLTH/PVvZIompVP/

authconfig --enableshadow --passalgo=sha512
selinux --enforcing
timezone --utc America/New_York

bootloader --location=mbr --driveorder=sda --append="crashkernel=auto rhgb quiet net.ifnames=0 biosdevname=0"
network --bootproto=dhcp --device=link --activate --onboot=on

# disk layout
zerombr
clearpart --all --drives=sda
autopart

reboot

%packages
@development
@graphical-server-environment
epel-release

# For oz/imagefactory
oz
python3-pycurl
python3-libguestfs
python3-zope-interface
python3-libxml2
python3-httplib2
python3-libs
python3-m2crypto

# For KVM/Virt
@virtualization-hypervisor
@virtualization-client
libguestfs-tools

# Ruby
ruby
ruby-devel

# VNC
tigervnc
tigervnc-server
tigervnc-server-module

%end

%post --log=/root/anaconda-post.log

mkdir -p /build/fileshare /build/images /build/isos /build/logs /build/storage

pushd /build
  git clone https://www.github.com/ManageIQ/manageiq-appliance-build.git
  ln -s manageiq-appliance-build/bin bin
  git clone https://www.github.com/redhat-imaging/imagefactory.git
popd

pip3 install oauth2 cherrypy boto monotonic

pushd /build/imagefactory/scripts
  sed -i 's/python2\.7/python3\.6/' imagefactory_dev_setup.sh
  ./imagefactory_dev_setup.sh
popd

pushd /build/manageiq-appliance-build/scripts
  gem install bundler
  export PATH="/usr/local/bin:${PATH}"
  bundle install
popd

echo "export LIBGUESTFS_BACKEND=direct" >> /root/.bash_profile

# VNC/GNOME Configuration
systemctl set-default graphical
sed -i 's/^#WaylandEnable.*/WaylandEnable=False/' /etc/gdm/custom.conf

firewall-offline-cmd --add-service vnc-server

sed -i 's/^#options kvm_intel.*/options kvm_intel nested=1/' /etc/modprobe.d/kvm.conf

# needed to test this kickstart file in Fusion
kversion=$(rpm -q kernel --qf '%{version}-%{release}.%{arch}\n')
ramfsfile="/boot/initramfs-$kversion.img"
dracut --force --add-drivers "vmw_pvscsi mptspi" $ramfsfile $kversion

cat > /bin/vncsetup-script.sh <<EOF
#!/bin/bash
#loginctl enable-linger
mkdir -p /root/.config/systemd/user
cp /usr/lib/systemd/user/vncserver@.service /root/.config/systemd/user/
echo "Enter VNC password"
vncpasswd
systemctl --user daemon-reload
systemctl --user enable vncserver@:1.service
EOF

chmod +x /bin/vncsetup-script.sh

chvt 1

%end
