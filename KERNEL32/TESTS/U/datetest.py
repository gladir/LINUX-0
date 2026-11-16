#!/usr/bin/env python3
# @author: Sylvain Maltais (support@gladir.com)
# @created: 2026
# @website(https://www.gladir.com/linux-0)
# @description: date de USR/DATE.PAS contre GNU date (hote) : -d (epoch, ISO,
#   americain, mois en lettres, jours de la semaine, relatif, fuseaux), -u,
#   -R, -I, formats strftime, sur plusieurs fuseaux (heure d'ete comprise).
#   usage : datetest.py ./DATE
import os, subprocess, sys

PROG = sys.argv[1]
ZONES = ['UTC', 'Europe/Paris', 'America/New_York', 'Asia/Kolkata',
         'Australia/Sydney']
DATES = ['@1700000000', '@0', '@1718000000', '2024-02-29 13:45:10',
         '2024-07-04T08:09:10Z', '2023-12-31 23:59:59',
         '2024-10-27 01:30', '06/15/2024 3pm', '15 June 2024',
         'June 15, 2024 11:05 am', '2024-01-31 +1 month',
         '2024-02-29 +1 year', '2024-03-10 -3 days', '2024-05-05 2 weeks ago',
         '2024-06-01 12:00 UTC', '2024-06-01 12:00 +0530',
         '2024-06-01 12:00 -0300', '2024-06-01 tomorrow',
         '2024-06-01 yesterday',
         '2024-06-01 next month', '2024-06-01 last year',
         'TZ="Asia/Tokyo" 2024-06-01 12:00',
         'TZ="America/Los_Angeles" @1718000000',
'20240601']
FORMATS = ['%Y-%m-%d %H:%M:%S %Z %z', '%a %A %b %B %d %e %j',
           '%U %W %V %G %g %u %w',
           '%D %F %T %R %r %p %P %I %l %k %y %C %s',
           '%-d/%-m %_d %^a %10Y %:z %%',
           '%c|%x|%X']
bad = 0
n = 0


def run(cmd, tz):
    env = dict(os.environ, TZ=tz, LC_ALL='C', LANGUAGE='C')
    r = subprocess.run(cmd, env=env, capture_output=True, text=True)
    return r.stdout.strip(), r.returncode


for tz in ZONES:
    for d in DATES:
        for f in ('+%F %T %Z %z', '+%s'):
            a, ra = run([PROG, '-d', d, f], tz)
            b, rb = run(['date', '-d', d, f], tz)
            n += 1
            if a != b:
                bad += 1
                if bad < 25:
                    print('DIFF', tz, repr(d), f, '|', a, '|', b)
    for f in FORMATS:
        for d in ('@1718000000', '2024-12-30 10:00', '2021-01-03 10:00',
                  '2020-12-31 23:00'):
            a, _ = run([PROG, '-d', d, '+' + f], tz)
            b, _ = run(['date', '-d', d, '+' + f], tz)
            n += 1
            if a != b:
                bad += 1
                if bad < 25:
                    print('DIFF', tz, d, f, '|', a, '|', b)
    for opt in (['-R'], ['-I'], ['-Iseconds'], ['-Iminutes'], ['-u', '+%H %Z'],
                ['+%Z'], ['-d', 'next friday', '+%F'],
                ['-d', 'tomorrow', '+%F'],
                ['-d', '3 days ago', '+%F'],
                ['-d', 'yesterday 12:00', '+%F %T'],
                ['-d', 'last month', '+%Y-%m'], ['-d', 'monday', '+%F']):
        a, _ = run([PROG] + opt, tz)
        b, _ = run(['date'] + opt, tz)
        n += 1
        if a != b:
            bad += 1
            if bad < 25:
                print('DIFF', tz, opt, '|', a, '|', b)
print('date : %d comparaisons, %d ecarts' % (n, bad))
sys.exit(1 if bad else 0)
