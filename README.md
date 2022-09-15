# My Docker Development Environment

This is a repo for creating a docker image which I use to develop my research projects. It is not for deployment, and typically neither are the applications developed using it. It is not intended to be lightweight or plug-and-play ready, but where possible, I tried to make it extensible for other users.

## Features

#### SSH & SFTP Access
A non-privileged run of `sshd` on the container. combined with port forwarding on a non-privileged port like `2022`, this allows direct `ssh` and `sftp` access to the container, useful for setting up a remote interpreter in PyCharm.

## Miniconda

Miniconda pre-installed, no significant packages added. Images should extend this one and run conda environment set up.