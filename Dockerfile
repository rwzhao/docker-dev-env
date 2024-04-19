FROM nvcr.io/nvidia/pytorch:24.03-py3

# default a user name
ARG user=rzhao17

# user id and group id, helpful to make these same as your host ones
ARG uid=501
ARG gid=20 

# copy this to an environment variable https://blog.bitsrc.io/how-to-pass-environment-info-during-docker-builds-1f7c5566dd0e
ENV USER=${user}  
ENV UID=${uid}
ENV GID=${gid}
# This environment variable will be used by openssh-server
ENV TZ=America/Los_Angeles

EXPOSE 2022
EXPOSE 7676
EXPOSE 7677
EXPOSE 8265
EXPOSE 6007

# # Remove any third-party apt sources to avoid issues with expiring keys. Then, install some basic utilities and python-dev
# RUN rm -f /etc/apt/sources.list.d/*.list && \
#     apt-get update && apt-get install -y \
#     curl \
#     zsh \
#     ca-certificates \
#     sudo \
#     git \
#     bzip2 \
#     wget \
#     libx11-6 \
#     python-dev \
#  && rm -rf /var/lib/apt/lists/*

# Create a working directory
RUN mkdir /soe
WORKDIR /soe

# Create a non-root user and give it a home directory
RUN echo "User: ${USER}" && \
    groupadd -g ${GID} -o ${USER} && \
    useradd -u ${UID} -g ${GID} ${USER} && \ 
    echo "${USER}:${USER}" | chpasswd  && \
    mkdir -p /home/${USER} && chown -R ${USER}:${USER} /home/${USER}

# install openssh-server
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone && \
    apt-get update && apt-get install -y openssh-server vim

# Setting up a non-privileged ssh directory for sshd
# see https://www.golinuxcloud.com/run-sshd-as-non-root-user-without-sudo
RUN mkdir -p /opt/ssh && \
    ssh-keygen -q -N "" -t dsa -f /opt/ssh/ssh_host_dsa_key && \
    ssh-keygen -q -N "" -t rsa -b 4096 -f /opt/ssh/ssh_host_rsa_key && \
    ssh-keygen -q -N "" -t ecdsa -f /opt/ssh/ssh_host_ecdsa_key && \
    ssh-keygen -q -N "" -t ed25519 -f /opt/ssh/ssh_host_ed25519_key

# Note the custom config defined here, which uses a non-privileged port, 
# rejects pass word auth, etc. See details in link above
COPY sshd_config /opt/ssh/sshd_config

# Set up a service for the user to be able to run. Modify on the fly to add env user we created
COPY sshd-1.service /etc/systemd/sshd-1.service
RUN sed -i 's/<PUT_USER_HERE>/$USER/' /etc/systemd/sshd-1.service && cat /etc/systemd/sshd-1.service

# Modify permissions to each folder so user can run
RUN chmod 600 /opt/ssh/* && \
    chmod 644 /opt/ssh/sshd_config && \
    chown ${USER}:${USER} /etc/systemd/sshd-1.service && \
    chown -R ${USER}:${USER} /opt/ssh/ && \
    mkdir -p  /home/${USER}/.ssh

# IMPORTANT: modified config prohibits password auth, preventing brute force (last step)
COPY id_rsa.pub /home/${USER}/.ssh/authorized_keys

# All users can use /home/${USER} as their home directory. Then, update permissions for .ssh to be more restrictive
ENV HOME=/home/${USER}
RUN mkdir $HOME/.cache $HOME/.config && \
    chmod -R 755 $HOME && \
    chmod -R 700 /home/${USER}/.ssh && \
    chmod 644 /home/${USER}/.ssh/authorized_keys



# work from the home directory
WORKDIR /home/${USER}

# Default powerline10k theme, no plugins installed, and set shell to zsh
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v1.1.2/zsh-in-docker.sh)" && \
    chsh -s /usr/bin/zsh ${USER}

# Copy my ssh config. Useful (for me) in pulling files onto container and attached volumes
# from resources I have access to.
COPY ssh_config /home/${USER}/.ssh/config

# Warning! It is generally not advised to trust public keys without checking them yourself. This allows me clone
# git with ssh on container/job launch without having to accept a fingerprint check (file contains ssh public keys 
# for github.com). Check these for yourself or remove this step. More detail here: https://serverfault.com/a/701637
COPY ssh_known_hosts /home/${USER}/.ssh/known_hosts

# Need to set user as owner of their home directory, now that we've populated things
RUN chown -R ${USER}:${USER} /home/${USER}

# Now continue with all actions as the non-privileged user
USER ${USER}

# Setup and install anaconda
RUN wget "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh" && \
    bash "Miniconda3-latest-Linux-x86_64.sh" -b -p "/home/${USER}/miniconda" && \
    miniconda/bin/conda init --all

# sone final setup: add this lint to the top of each shell file to turn off output in interactive modes
# this is required for SFTP to work
RUN echo "[[ "$-" != *i* ]] && return" > .bashrc && sed -i '1s/^/[[ "$-" != *i* ]] \&\& return\n/' .zshrc

# on start up, run openssh-server as non-privileged user!
CMD ["/usr/sbin/sshd","-D", "-f", "/opt/ssh/sshd_config",  "-E", "/tmp/sshd.log"]
