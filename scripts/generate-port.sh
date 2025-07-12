#!/bin/bash

# Menghasilkan nomor port dari 6000 hingga 19999, dipisahkan dengan koma
ports=$(seq -s, 6000 19999)

# Menampilkan hasil
echo $ports | termux-clipboard-set
