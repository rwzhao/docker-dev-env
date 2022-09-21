FROM nvidia/cuda:11.5.1-base-ubuntu20.04

# default a user name
ARG user=bking2

# user id and group id, helpful to make these same as your host ones
ARG uid=501
ARG gid=20 

# copy this to an environment variable https://blog.bitsrc.io/how-to-pass-environment-info-during-docker-builds-1f7c5566dd0e
ENV USER=${user}  
ENV UID=${uid}
ENV GID=${gid}

EXPOSE 2022
EXPOSE 7676
EXPOSE 7677
EXPOSE 8265
EXPOSE 6007

# Remove any third-party apt sources to avoid issues with expiring keys.
RUN rm -f /etc/apt/sources.list.d/*.list

# Install some basic utilities and python-dev
RUN apt-get update && apt-get install -y \
    curl \
    zsh \
    ca-certificates \
    sudo \
    git \
    bzip2 \
    wget \
    libx11-6 \
    python-dev \
 && rm -rf /var/lib/apt/lists/*

# Create a working directory
RUN mkdir /soe
WORKDIR /soe

# Create a non-root user and switch to it
RUN echo "User: ${USER}"
RUN groupadd -g ${GID} -o ${USER}
RUN useradd -u ${UID} -g ${GID} ${USER} && echo "${USER}:${USER}" | chpasswd
RUN mkdir -p /home/${USER} && chown -R ${USER}:${USER} /home/${USER}

# Adding the openssh-server
ENV TZ=America/Los_Angeles
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
RUN apt-get update && apt-get install -y openssh-server vim

# Setting up a non-privileged ssh directory for sshd
# see https://www.golinuxcloud.com/run-sshd-as-non-root-user-without-sudo
RUN mkdir -p /opt/ssh
RUN ssh-keygen -q -N "" -t dsa -f /opt/ssh/ssh_host_dsa_key
RUN ssh-keygen -q -N "" -t rsa -b 4096 -f /opt/ssh/ssh_host_rsa_key
RUN ssh-keygen -q -N "" -t ecdsa -f /opt/ssh/ssh_host_ecdsa_key
RUN ssh-keygen -q -N "" -t ed25519 -f /opt/ssh/ssh_host_ed25519_key

# Note the custom config defined here, which uses a non-privileged port, 
# rejects pass word auth, etc. See details in link above
COPY sshd_config /opt/ssh/sshd_config

# Set up a service for the user to be able to run. Modify on the fly to add env user we created
COPY sshd-1.service /etc/systemd/sshd-1.service
RUN sed -i 's/<PUT_USER_HERE>/$USER/' /etc/systemd/sshd-1.service
RUN cat /etc/systemd/sshd-1.service

# Modify permissions to each folder so user can run
RUN chmod 600 /opt/ssh/*
RUN chmod 644 /opt/ssh/sshd_config
RUN chown ${USER}:${USER} /etc/systemd/sshd-1.service
RUN chown -R ${USER}:${USER} /opt/ssh/

# IMPORTANT: modified config prohibits password auth, preventing brute force
RUN mkdir -p  /home/${USER}/.ssh
COPY id_rsa.pub /home/${USER}/.ssh/authorized_keys

# All users can use /home/${USER} as their home directory
ENV HOME=/home/${USER}
RUN mkdir $HOME/.cache $HOME/.config \
 && chmod -R 755 $HOME

 # update permissions for .ssh to be more restrictive
RUN chmod -R 700 /home/${USER}/.ssh
RUN chmod 644 /home/${USER}/.ssh/authorized_keys



# work from the home directory
WORKDIR /home/${USER}

# Default powerline10k theme, no plugins installed
RUN sh -c "$(wget -O- https://github.com/deluan/zsh-in-docker/releases/download/v1.1.2/zsh-in-docker.sh)"

# Set shell to zsh 
RUN chsh -s /usr/bin/zsh ${USER}

# Copy my ssh config. Useful (for me) in pulling files onto container and attached volumes
# from resources I have access to.
COPY ssh_config /home/${USER}/.ssh/config

# Need to set user as owner of their home directory, now that we've populated things
RUN chown -R ${USER}:${USER} /home/${USER}

# Now continue with all actions as the non-privileged user
USER ${USER}


RUN wget "https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"
RUN bash "Miniconda3-latest-Linux-x86_64.sh" -b -p "/home/${USER}/miniconda"
RUN miniconda/bin/conda init --all

# sone final setup: add this lint to the top of each shell file to turn off output in interactive modes
# this is required for SFTP to work
RUN echo "[[ "$-" != *i* ]] && return" > .bashrc
RUN sed -i '1s/^/[[ "$-" != *i* ]] \&\& return\n/' .zshrc

CMD ["/usr/sbin/sshd","-D", "-f", "/opt/ssh/sshd_config",  "-E", "/tmp/sshd.log"]
