FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

#####################################
# Locale setup
#####################################

RUN apt-get update && apt-get install -y \
    locales \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    unzip \
    git \
    openssh-client \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

RUN locale-gen en_US.UTF-8

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

############################
# Terraform
############################

ARG TERRAFORM_VERSION=1.6.6

RUN curl -fsSL https://apt.releases.hashicorp.com/gpg \
    | gpg --dearmor -o /usr/share/keyrings/hashicorp.gpg

RUN echo "deb [signed-by=/usr/share/keyrings/hashicorp.gpg] \
    https://apt.releases.hashicorp.com \
    $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/hashicorp.list

RUN apt-get update && apt-get install -y terraform \
    && terraform version

############################
# Ansible
############################

RUN pip3 install --no-cache-dir ansible

############################
# AWS CLI v2
############################

RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf aws awscliv2.zip

############################
# Workspace
############################

WORKDIR /workspace
SHELL ["/bin/bash", "-c"]
