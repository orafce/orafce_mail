#!/usr/bin/env python3
"""A capture SMTP server for the orafce_mail reproducers.

It answers just enough SMTP for libcurl to hand over a message and writes
everything it sees to a log file: commands prefixed with "C: ", and the
contents of DATA verbatim, so a reproducer can tell a header the extension
sent from an SMTP command the extension was tricked into sending.
"""

import socket
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 52525
OUT = sys.argv[2] if len(sys.argv) > 2 else "/tmp/orafce_mail_sink.log"


def serve_one(conn, log):
    stream = conn.makefile("rwb", buffering=0)
    stream.write(b"220 orafce-mail-reproducer ESMTP\r\n")
    in_data = False

    while True:
        line = stream.readline()
        if not line:
            return

        if in_data:
            log.write(line)
            log.flush()
            if line == b".\r\n":
                in_data = False
                stream.write(b"250 Ok\r\n")
            continue

        log.write(b"C: " + line)
        log.flush()

        command = line.strip().upper()
        if command.startswith(b"EHLO"):
            stream.write(b"250-orafce-mail-reproducer\r\n250 SIZE 100000000\r\n")
        elif command.startswith(b"DATA"):
            stream.write(b"354 End data with <CR><LF>.<CR><LF>\r\n")
            in_data = True
        elif command.startswith(b"QUIT"):
            stream.write(b"221 Bye\r\n")
            return
        else:
            stream.write(b"250 Ok\r\n")


def main():
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    listener.bind(("127.0.0.1", PORT))
    listener.listen(5)

    sys.stderr.write("listening on 127.0.0.1:%d\n" % PORT)
    sys.stderr.flush()

    with open(OUT, "ab", buffering=0) as log:
        while True:
            conn, _ = listener.accept()
            try:
                serve_one(conn, log)
            except OSError:
                pass
            finally:
                conn.close()


if __name__ == "__main__":
    main()
