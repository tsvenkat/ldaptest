#!/bin/bash

MYSQL=`which mysql`

Q1="CREATE DATABASE slurm_complete_db DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci ;"
Q2="CREATE DATABASE slurm_acct_db DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci ;"
Q3="CREATE USER 'slurm'@'%' IDENTIFIED WITH caching_sha2_password BY '' ;"
Q4="GRANT ALL ON slurm_complete_db.* TO 'slurm'@'%';"
Q5="GRANT ALL ON slurm_acct_db.* TO 'slurm'@'%';"

$MYSQL -uroot -e "$SQL"
