#!/usr/bin/env python3
# dongle (imprint_dongle-logging) の USB-CDC ログから、電池残量と接続イベントの行だけを
# 抜き出して追記する。打鍵内容が出る DBG ログなので、生ログは決して保存しない。
#
#   python3 scripts/battery-log.py '/dev/cu.usbmodem*' /path/to/battery-log.txt
#
# 前提: dongle に --logging ビルドが焼いてあり、かつ半体の残量を読むなら
# CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING=y を一時的に足してあること
# (製品 config には入れない: 表示先が無いのに定期 GATT read で半体を起こす)。
# DTR を上げないと ZMK 側がログを吐かない (ioctl TIOCMBIS で DTR|RTS)。
#
# ポートを 1 本に決め打ちしない: 同じマシンに別の ZMK デバイス (PIO_USB HID Host 等) が
# 居ると取り違える上、dongle を抜き差しすると番号が変わる。glob に一致する CDC を
# 全部同時に開いて select し、一致行を吐いたものだけが結果に残る。5 秒ごとに再スキャン
# するので、抜き差し後の新しいポートも自動で拾う。
#
# BAS 通知は「値が変化した時だけ」出る = 満充電の平坦区間は無音が正常。確実に読み直すには
# dongle を抜き差しする (再接続時に各 slot を読む)。深い sleep 中の半体は切断されていて
# 読めない (打鍵で起こしてから読む)。半体 2 台の値は slot 番号なしで出るため値の系列で判別する。
# 依存は stdlib のみ (リポジトリの低依存方針)。
import os, sys, time, termios, fcntl, struct, select, re, glob, datetime

pattern, logfile = sys.argv[1], sys.argv[2]
pat = re.compile(r'[Bb]attery level|BATTERY LEVEL|peripheral.*(connected|disconnected)|split_central.*(connected|Connected)'
                 r'|security failed|le_param|interval \d+ latency|conn param'
                 # &ext_power は dongle 構成では常に失敗する: central に EXT_POWER デバイスが
                 # 無く、GLOBAL 転送の前段の convert が -EIO を返して打ち切るので、半体には届かない。
                 # よって "Unable to retrieve ext_power device" は失敗の証拠。レールは
                 # config/ext_power_off.dtsi で切ってある。
                 r'|ext.?power|DIAG |connection params', re.I)  # connection params = central.c の le_param_updated  # DIAG = 一時診断 patch (計測のたび使い捨て) の行

def stamp():
    return f"{datetime.datetime.now():%m-%d %H:%M:%S}"

def emit(line):
    out = f"{stamp()} {line}"
    with open(logfile, 'a') as f:
        f.write(out + '\n')
    print(out, flush=True)

def open_port(dev):
    fd = os.open(dev, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    a = termios.tcgetattr(fd); a[0] = 0; a[1] = 0
    a[2] = termios.CS8 | termios.CREAD | termios.CLOCAL; a[3] = 0
    a[4] = a[5] = termios.B115200
    termios.tcsetattr(fd, termios.TCSANOW, a)
    fcntl.ioctl(fd, 0x8004746c, struct.pack('I', 0x006))  # TIOCMBIS DTR|RTS
    return fd

fds, bufs, next_scan = {}, {}, 0.0
while True:
    now = time.time()
    if now >= next_scan:
        next_scan = now + 0.5
        for dev in sorted(glob.glob(pattern)):
            if dev in fds:
                continue
            try:
                fds[dev] = open_port(dev); bufs[dev] = b''
                print(f"{stamp()} PORT open {dev}", flush=True)
            except Exception:
                # 抜き差しの最中は open は通っても termios/ioctl が落ちる。
                # ここで死ぬと数時間の計測が無言で止まるので、握り潰して次の周回で拾う。
                fds.pop(dev, None); bufs.pop(dev, None)
    if not fds:
        time.sleep(1); continue
    rlist, _, _ = select.select(list(fds.values()), [], [], 1.0)
    for dev, fd in list(fds.items()):
        if fd not in rlist:
            continue
        try:
            chunk = os.read(fd, 4096)
        except (BlockingIOError, InterruptedError):
            continue
        except OSError:
            chunk = b''
        if not chunk:
            os.close(fd); fds.pop(dev); bufs.pop(dev, None)
            print(f"{stamp()} PORT lost {dev}", flush=True)
            continue
        bufs[dev] += chunk
        while b'\n' in bufs[dev]:
            raw, bufs[dev] = bufs[dev].split(b'\n', 1)
            s = re.sub(r'\x1b\[[0-9;]*m', '', raw.decode('utf-8', 'replace')).strip()
            if pat.search(s) and 'Setting BAS GATT' not in s:  # dongle 自身(電池なし)の読みは捨てる
                emit(s)
