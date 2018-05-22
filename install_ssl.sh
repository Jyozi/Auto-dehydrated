#!/bin/sh -eu

SCRIPT_PATH=`echo $(cd $(dirname $0);pwd)`
source ${SCRIPT_PATH}/config.sh

set -eu
# dehydratedインストール
if [ -e /opt/dehydrated/accounts ]; then
	echo "Account has already been created."
else
	echo "Remove /opt/dehydrated"
	rm -rf /opt/dehydrated

	echo "Download dehydrated -> /opt/dehydrated/"
	git clone https://github.com/lukas2511/dehydrated.git /opt/dehydrated

	echo "Copy /opt/dehydrated/docs/examples/config -> /otp/dehydrated/config"
	cp /opt/dehydrated/docs/examples/config /opt/dehydrated/config

	echo "Sed /opt/dehydrated/config:#WELLKNONWN=/var/www/dehydrated/ -> WELLKONWN=/var/www/dehydrated/"
	sed -i -e 's/#WELLKNOWN/WELLKNOWN/g' /opt/dehydrated/config

	echo "Make directory -> /var/www/dehydrated"
	mkdir -p /var/www/dehydrated
	chmod 755 /var/www/dehydrated

	echo "Create account -> /opt/dehydrated/account"
	/opt/dehydrated/dehydrated --register --accept-terms
fi

# Webサーバ検出とドメイン検出
# 設定ファイルにwwwが付いているものは削除しています。
echo -n "Search WEB Server -> "
WEBSERVER=`netstat -untap | grep ":80 " | awk '{print substr($0, index($0, "/"))}' | sed -e 's/^.//g'`
if [[ `echo $WEBSERVER | grep nginx` ]]; then
	WEBSERVER_TYPE=0 # nginx: 0, httpd: 1
	if [[ -v LETS_ENC_DOMAINS ]]; then
		DOMAINS="`echo ${LETS_ENC_DOMAINS} | sed 's/ /\n/g'`"
        else
		DOMAINS="`cat /etc/nginx/conf.d/*.conf | grep "server_name" | \
		  	sed -e 's/^[ ]*//g' | sed -e '/^#/d' | sed -e 's/;//g' | uniq | awk '{print($2)}'`"
	fi
	chown -R nginx:nginx /var/www/dehydrated/
	WEBSERVER=`echo $WEBSERVER | grep nginx`
	CONFIG=`cat << EOS
location ^~ /.well-known/acme-challenge/ {
    alias /var/www/dehydrated/;
}
EOS
`
elif [[ `echo $WEBSERVER | grep httpd` ]]; then
	WEBSERVER_TYPE=1 # nginx: 0, httpd 1
	if [[ -v LETS_ENC_DOMAINS ]]; then
                DOMAINS="`echo ${LETS_ENC_DOMAINS} | sed 's/ /\n/g'`"
        else
		DOMAINS="`cat /etc/httpd/conf.d/*.conf | grep "ServerName" | \
		  	sed -e 's/^[ ]*//g' | sed -e '/^#/d' |uniq | awk '{print($2)}'`"
	fi
	chown -R apache:apache /var/www/dehydrated/
	WEBSERVER=`echo $WEBSERVER | grep httpd`
        CONFIG=`cat << EOS
Alias /.well-known/acme-challenge /var/www/dehydrated

<Directory "/var/www/dehydrated">
        Options None
        AllowOverride None

        Require all granted
</Directory>
EOS
`

else
	echo "WEBSERVER is not running."
	exit 0;
fi
echo $WEBSERVER

# ドメイン紐付け確認
echo "---Search Domain---"
DOMAINS_TXT=""
while read line
do
	check_domain=$line
	if [[ `echo $check_domain | grep "www"` ]]; then
		check_domain=`echo $check_domain | sed -e 's/www.//g'`
	fi
        if [[ `nslookup $check_domain | grep "Name"` ]]; then
        	DOMAINS_TXT=$DOMAINS_TXT$line"\n"
		echo "-> $line"
	fi
done <<END
$DOMAINS
END
if [ "$DOMAINS_TXT" == "" ]; then
	echo "Domain is not define!"
	echo "-------------------"
	exit 0
fi
echo "-------------------"

# domains.txtを出力
DOMAINS_TXT=`echo -en $DOMAINS_TXT`
echo "Make domains.txt -> /opt/dehydrated/domains.txt"
echo "---domains.txt---"
echo -e "$DOMAINS_TXT"
echo "-----------------"
echo -e "$DOMAINS_TXT" > /opt/dehydrated/domains.txt


# 手動作業を出力
CERTS_FILES=""
while read line
do
	if [ $WEBSERVER_TYPE -eq 0 ]; then
		CERTS_FILES=$CERTS_FILES`cat << EOS
--------------------
# Cerificate about [$line]
ssl_certificate /opt/dehydrated/certs/$line/fullchain.pem;
ssl_certificate_key /opt/dehydrated/certs/$line/privkey.pem;
--------------------
EOS
`
	else 
		CERTS_FILES=$CERTS_FILES`cat << EOS
--------------------
# Cerificate about [$line]
SSLCertificateFile /opt/dehydrated/certs/$line/fullchain.pem
SSLCertificateKeyFile /opt/dehydrated/certs/$line/privkey.pem
--------------------
EOS
`
	fi
done <<END
$DOMAINS_TXT
END


cat << EOS


--------------------------------------------------------------

1.
Let's Encrypt need to access :80/well-known/acme-challenge/
Please set this conf to $WEBSERVER conf.
---
$CONFIG
---

2.
Run command if you set these conf
---
/opt/dehydrated/dehydrated -c --accept-terms
---

3.
Please set this SSLconf to $WEBSERVER conf.
---
$CERTS_FILES
---

-----------------------------------------------------------------
EOS
