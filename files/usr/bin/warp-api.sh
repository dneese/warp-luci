warp_ping() {
   for EP in engage.cloudflareclient.com 162.159.192.1 162.159.193.1 188.114.96.1 188.114.97.1; do
     # Попробуем разные форматы вывода ping
     RESULT=$(ping -c 3 -W 2 "$EP" 2>/dev/null)
     
     # Ищем avg в разных форматах
     AVG=$(echo "$RESULT" | grep -oE 'min/avg/max|rtt min/avg/max' | head -1)
     if [ -n "$AVG" ]; then
       # Формат: min/avg/max/stddev = X.XXX/Y.YYY/Z.ZZZ/W.WWW ms
       AVG=$(echo "$RESULT" | grep -oE '[0-9.]+/[0-9.]+/[0-9.]+' | cut -d/ -f2)
     else
       # Альтернативный формат с time=X.Xms
       AVG=$(echo "$RESULT" | grep -oE 'time=[0-9.]+ ms' | cut -d= -f2 | cut -d' ' -f1)
     fi
     
     [ -z "$AVG" ] && AVG="—"
     echo "$EP: $AVG ms"
   done
}
