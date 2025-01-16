FROM jenkins/jenkins:lts

# Define arguments for Terraform and Ansible versions
ARG TF_VERSION=1.8.5
ARG ANSIBLE_VERSION=10

USER root

# Install necessary tools like wget and unzip before downloading Terraform
RUN apt-get update && \
    apt-get install -y wget unzip python3-venv && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean

# Use the TF_VERSION argument to download and install the specified version of Terraform
RUN wget https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip && \
    unzip terraform_${TF_VERSION}_linux_amd64.zip && \
    mv terraform /usr/local/bin && \
    rm terraform_${TF_VERSION}_linux_amd64.zip

# Create a virtual environment for Python and activate it
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Use the ANSIBLE_VERSION argument to install the specified version of Ansible within the virtual environment
RUN pip install --upgrade pip cffi && \
    pip install ansible==${ANSIBLE_VERSION} && \
    pip install mitogen ansible-lint jmespath && \
    pip install --upgrade pywinrm

# Drop back to the regular jenkins user - good practice
USER jenkins