# coturn TURN Server — Ansible Deploy

Ansible-плейбук для автоматического развёртывания coturn TURN/STUN сервера
на любую Ubuntu-машину.

## Структура

```
ansible/
├── deploy.yml              — главный плейбук
├── inventory.ini           — список серверов
├── vars/
│   ├── main.yml            — все настройки (IP, домен, порты)
│   └── secrets.yml         — пароль TURN (шифровать ansible-vault)
├── templates/
│   └── env.j2              — шаблон .env для coturn
└── files/
    ├── coturn.conf.template
    ├── docker-compose.yml
    └── entrypoint.sh
```

---

## Быстрый старт

### 1. Указать сервер

Отредактировать `inventory.ini`:
```ini
[turn_servers]
turn1 ansible_host=<IP сервера> ansible_user=root
```

### 2. Настроить параметры

Отредактировать `vars/main.yml`. Для нового сервера достаточно изменить **два параметра** в начале файла — всё остальное выводится из них автоматически:

```yaml
server_ip: "185.219.83.158"   # публичный IP сервера
domain: "ice.valdi.sarl"      # домен для сертификата и TURN realm
```

Производные значения (не требуют изменений в обычном случае):

| Параметр | Выводится из | Описание |
|---|---|---|
| `external_ip` | `server_ip` | IP для STUN mapped-address |
| `relay_ip` | `server_ip` | IP для relay-сокетов |
| `realm` | `domain` | TURN realm |
| `certbot_domain` | `domain` | Домен для сертификата |
| `certbot_email` | `domain` | Email для Let's Encrypt |
| `cert_domain_folder` | `domain` | Папка внутри `letsencrypt/live/` |

Остальные параметры:

| Параметр | Описание |
|---|---|
| `cert_source` | `certbot` или `manual` |
| `manual_cert_dir` | Путь к директории с сертификатом (только для `manual`) |
| `turn_user` | Имя пользователя TURN |
| `auth_mode` | `password` или `noauth` |
| `min_port` / `max_port` | Диапазон relay-портов UDP |

### 3. Зашифровать пароль

```sh
ansible-vault encrypt vars/secrets.yml
```

Перед шифрованием установить `turn_password` в `vars/secrets.yml`.

### 4. Запустить деплой

```sh
ansible-playbook -i inventory.ini deploy.yml --ask-vault-pass
```

---

## Что делает плейбук

1. **Docker** — проверяет наличие, устанавливает из официального репозитория если нет
2. **certbot** — устанавливает и получает сертификат `--standalone` (если `cert_source=certbot`)
3. **Файлы** — создаёт `/opt/coturn/`, копирует файлы, генерирует `.env` (mode 0600)
4. **Firewall** — открывает порты в ufw (3478 UDP/TCP, 5349 TCP/UDP, relay range UDP)
5. **Запуск** — `docker compose up -d`
6. **Cron** — ежедневное обновление сертификата и перезапуск coturn в 04:00

---

## Источник сертификата

### certbot (по умолчанию)

Плейбук устанавливает certbot и получает сертификат автоматически.
Порт 80 должен быть свободен во время первого запуска.

```yaml
cert_source: "certbot"
# domain и server_ip уже заданы выше — certbot использует их автоматически
```

Внутри контейнера сертификат доступен по пути:
```
/etc/coturn/certs/live/<domain>/fullchain.pem
```

### manual

Сертификат уже есть на сервере. Укажите полный путь к директории
с `fullchain.pem` и `privkey.pem`:

```yaml
cert_source: "manual"
manual_cert_dir: "/etc/ssl/certs/mycert"
```

Плейбук смонтирует эту директорию напрямую как `/etc/coturn/certs`.
Путь внутри контейнера: `/etc/coturn/certs/fullchain.pem`.

> Если сертификат от nginx-proxy-manager, укажите полный путь до папки
> с симлинками, и дополнительно смонтируйте `archive/` — или скопируйте
> реальные файлы в отдельную директорию:
> ```sh
> cp /opt/nginx-proxy-manager/letsencrypt/archive/npm-29/fullchain1.pem \
>    /etc/ssl/coturn/fullchain.pem
> cp /opt/nginx-proxy-manager/letsencrypt/archive/npm-29/privkey1.pem \
>    /etc/ssl/coturn/privkey.pem
> ```

---

## Переключение режима аутентификации

Изменить в `vars/main.yml`:
```yaml
auth_mode: "password"   # или noauth
```

Применить без полного деплоя:
```sh
ansible-playbook -i inventory.ini deploy.yml --ask-vault-pass --tags config
```

> Пересборка образа не нужна — только перезапуск контейнера.

---

## Полезные команды

```sh
# Деплой
ansible-playbook -i inventory.ini deploy.yml --ask-vault-pass

# Проверка без применения
ansible-playbook -i inventory.ini deploy.yml --check --ask-vault-pass

# Только обновить конфиг
ansible-playbook -i inventory.ini deploy.yml --ask-vault-pass --tags config

# Редактировать зашифрованный файл паролей
ansible-vault edit vars/secrets.yml

# Проверить доступность сервера
ansible -i inventory.ini turn_servers -m ping
```

---

## Проверка после деплоя

```sh
# Логи coturn
ssh root@<IP> "docker compose -f /opt/coturn/docker-compose.yml logs coturn"

# Тест STUN с локальной машины
python3 ../stun_test.py
```

Ожидаемый результат `stun_test.py`:
```
Response from: ('<IP сервера>', 3478)
STUN OK
```
