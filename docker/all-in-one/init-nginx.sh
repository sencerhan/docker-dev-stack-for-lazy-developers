#!/bin/bash

# Nginx konfigürasyonunu test et
nginx -t

# Nginx'i başlat
exec nginx -g "daemon off;"
