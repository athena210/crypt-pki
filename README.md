# crypt-pki
Tool to manipulate a PKI stored inside LUKS container

Утилита является оберткой для `easy-rsa` и предлагает комплекс операций по созданию и монтированию LUKS криптоконтейнера с файловой системой внутри. На файловой системе размещается копия `easy-rsa`, записанная туда при создании контейнера, а также PKI и шаблоны для экспорта пользовательских и серверных конфигов openvpn. С `easy-rsa` можно создавать ключи произвольного назначения, а выгружать их можно как в виде файлов или pkcs12 (pfx) контейнеров, так и записанных в конфиг ovpn на основе заготовленных шаблонов.

Для работы с утилитой требуются права root для монтирования криптоконтейнера, а также `cryptsetup`, `base64`, `zip`, `openvpn`.

Ниже пример создания ключей для двух серверов openvpn и двух клиентов, а также выгрузки подготовленных для них конфигов. Сервера используют `tls-crypt-v2`, которые текже генерируются в примере. Более подробно параметры утилиты и примеры использования содержатся в `crypt-pki --help`

```shell
# Создать контейнер и ключ. Ключ будет записан в ./ctkey.secret
CTKEY=$(./crypt-pki ./vault13 --init) && echo "$CTKEY" > ./ctkey.secret
```

Для работы с контейнером утилита читает ключ из переменной окружения `CTKEY`
```shell
# Получить ключ
read -rsp "CTKEY: " CTKEY
export CTKEY
mkdir ./export

# Создать внутри контейнера CA и CRL
./crypt-pki ./container --exec --cmd "easy-rsa/easyrsa --req-cn=my_CA build-ca nopass"
./crypt-pki ./container --crl

# Загрузить в контейнер шаблоны для будущего экспорта конфигов
./crypt-pki ./container --loadtemplate --file ./tpl/c1-strong-android-in
./crypt-pki ./container --loadtemplate --file ./tpl/c1-strong-win-api
./crypt-pki ./container --loadtemplate --file ./tpl/s1-strong

# Ключи и конфиги для сервера1 (vpn1.example.com)
./crypt-pki ./container --newreq --internalname vpn1.example.com --nopass
./crypt-pki ./container --signserver --internalname vpn1.example.com
./crypt-pki ./container --newtc2 --internalname vpn1.example.com
# Экспорт
./crypt-pki ./container --export-config --template s1-strong --internalname vpn1.example.com --file ./export/vpn1_server-strong.conf
./crypt-pki ./container --export-zip --internalname vpn1.example.com --file ./export/vpn1_server_keys.zip

# Ключи и конфиги для сервера2 (vpn2.example.com)
./crypt-pki ./container --newreq --internalname vpn2.example.com --nopass
./crypt-pki ./container --signserver --internalname vpn2.example.com
./crypt-pki ./container --newtc2 --internalname vpn2.example.com
# Экспорт
./crypt-pki ./container --export-config --template s1-strong --internalname vpn2.example.com --file ./export/ivpn_server-strong.conf.j2
./crypt-pki ./container --export-zip --internalname vpn1.example.com --file ./export/ivpn_server_keys.zip

# Ключи и конфиги для клиента user1
./crypt-pki ./container --newreq --internalname user1 --nopass
./crypt-pki ./container --signclient --internalname user1
./crypt-pki ./container --newtc2 --internalname user1 --servertc2 vpn1.example.com
./crypt-pki ./container --newtc2 --internalname user1 --servertc2 vpn2.example.com
# export
./crypt-pki ./container --export-chain --internalname user1 --file ./export/user1.pfx
./crypt-pki ./container --export-config --template c1-strong-android-api --internalname user1 --servertc2 vpn1.example.com --file ./export/user1-vpn1.ovpn
./crypt-pki ./container --export-config --template c1-strong-android-api --internalname user1 --servertc2 vpn2.example.com --file ./export/user1-vpn2.ovpn

# Ключи и конфиги для клиента user2
./crypt-pki ./container --newreq --internalname user2 --nopass
./crypt-pki ./container --signclient --internalname user2
./crypt-pki ./container --newtc2 --internalname user2 --servertc2 vpn1.example.com
./crypt-pki ./container --newtc2 --internalname user2 --servertc2 vpn2.example.com
# export
./crypt-pki ./container --export-chain --internalname user2 --file ./export/user2.pfx
./crypt-pki ./container --export-config --template c1-strong-win-api --internalname user2 --servertc2 vpn1.example.com --file ./export/user2-vpn1.ovpn
./crypt-pki ./container --export-config --template c1-strong-win-api --internalname user2 --servertc2 vpn2.example.com --file ./export/user2-vpn2.ovpn
```

В предложенном примере заранее заготовленные шаблоны загружаются из каталога `./tpl/`. К проекту прилагается скрипт `prepare_templates.sh` который на основе переменных из `templates.var` кастомизирует шаблоны `./tpl/prepare/` для создания рабочих шаблонов. Может пригодиться в подготовке более гибкого плана развертывания на множество серверов и клиентов.
