#! /bin/bash

if [ "$1" = "help" ]; then
    echo "---------------------------------------------------------"
    echo "| Active Directory domain join script"
    echo "| Interactive mode:"
    echo "| Usage: sudo bash ./adjoin"
    echo "| Non-interactive:
    echo "| Usage: sudo bash ./adjoin [domain] [user] [password]"
    echo "| Enter all parameters for non-interactive mode"
    echo "|
    echo "---------------------------------------------------------"
    exit 1
fi

if [ -n "$3" ]; then
    clear
    echo "!! Password detected on command line.  History will be cleared for security purposes."
    history -c
fi
echo " -> Installing prerequsites, if needed..."
sudo yum install -q -y nano sssd realmd oddjob oddjob-mkhomedir adcli samba-common samba-common-tools krb5-workstation openldap-clients policycoreutils-python > /tmp/yumad.log

echo "Checking for AD membership..."
if [ -z "`realm list`" ]; then
    echo " -> No domain found.  Begining AD join subscript..."
    if [ -n "$1" ]; then
        realmad="$1"
    else
        addomain=`grep -P "\w+.local*" /etc/resolv.conf -m 1 -o`
        read -ep " -> Domain to join: " -i "$addomain" realmad
    fi
    if [ -n "$2" ]; then
        realmuser="$2"
    else
        read -ep " -> Username for $addomain: " realmuser
    fi
    if [ -n "$3" ]; then
        echo " -> Attempting to join Active Directory domain [$realmad] using [$realmuser] and password..."
        echo "$3" | sudo realm join --user=$realmuser $realmad
    else
        sudo realm join --user=$realmuser $realmad
    fi
    p=`ping $realmad -c 2`
    echo " -> Creating /etc/sudoers.d/domain..."
    echo "#add domain admins group to /etc/sudoers" > /etc/sudoers.d/domain
    echo "%$realmad\\\Sudoers ALL=(ALL)ALL" >> /etc/sudoers.d/domain
    echo "%$realmad\\\Domain\ Admins ALL=(ALL)ALL" >> /etc/sudoers.d/domain
    echo "%Domain\ Admins ALL=(ALL)ALL" >> /etc/sudoers.d/domain
    echo "%Sudoers ALL=(ALL)ALL" >> /etc/sudoers.d/domain
    if [ -n "`realm list`" ]; then
        echo " -\ Successfully joined to $realmad"
    else
        echo " -\ Failed to join $realmad"
    fi
else
    echo " -\ Machine is already a member of `realm list -n` domain.  Skipping join."
fi

echo "Fixing up /etc/sssd/sssd.conf..."
# Get DNS server for machine from /etc/resolv
dnsserver=`grep -P "(?<=nameserver\s).*" -o /etc/resolv.conf -m 1`

# Separate any [domain] entries from [sssd] entries in the event they exist
confdom=`sed -n '/\[domain/,$p' /etc/sssd/sssd.conf`
confsssd=`sed -n '/\[sssd/,/\[/p' /etc/sssd/sssd.conf | grep -v "\[d" | grep -v "^dyn" | grep "^\S+" -P`
# Create a new file with clean [sssd]
echo "$confsssd" > /etc/sssd/sssd.conf
echo " -> Adding dyndns_* information for DNS server $dnsserver..."
echo "dyndns_server = $dnsserver" >> /etc/sssd/sssd.conf
echo "dyndns_update = true" >> /etc/sssd/sssd.conf
echo "dyndns_refresh_interval = 3600" >> /etc/sssd/sssd.conf
echo "dyndns_update_ptr = true" >> /etc/sssd/sssd.conf
echo "dyndns_ttl = 3600" >> /etc/sssd/sssd.conf
echo "" >> /etc/sssd/sssd.conf
echo "$confdom" >> /etc/sssd/sssd.conf

echo "Fixing up AD configuration files..."
# Fixup /etc/sssd/sssd.conf for AD auth
sudo sed -i 's/use_fully_qualified_names.*/use_fully_qualified_names = False/' /etc/sssd/sssd.conf
sudo sed -i 's/fallback_homedir.*/fallback_homedir = \/home\/%u/' /etc/sssd/sssd.conf
sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config
echo " -> Restarting sssd and sshd..."
sudo systemctl restart sssd;sudo systemctl daemon-reload;sudo systemctl restart sshd
echo " -\ Complete"
if [ -n "$3" ]; then
    echo "!! Password detected on command line.  Be sure to clear command history with 'history -c'"
fi
