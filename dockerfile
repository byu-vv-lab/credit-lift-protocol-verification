FROM coqorg/coq:latest
RUN git clone https://github.com/byu-vv-lab/credit-lift-protocol-verification.git
RUN chmod 777 ./credit-lift-protocol-verification/verifyMyChips.sh
RUN chmod 777 ./credit-lift-protocol-verification/verifyCoqMapping.sh
RUN sudo apt update
RUN sudo apt -y install spin
RUN sudo apt -y install vim-gtk
RUN mkdir -p ~/.vim/pack/coq/start
RUN git clone https://github.com/whonore/Coqtail.git ~/.vim/pack/coq/start/Coqtail
RUN vim +helptags\ ~/.vim/pack/coq/start/Coqtail/doc +q
