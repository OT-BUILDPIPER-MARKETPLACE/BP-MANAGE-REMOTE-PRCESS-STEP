# BP-MANAGE-REMOTE-PRCESS-STEP

This step facilitates performing a different task or command on the server.
## Setup
* Clone the code available at [BP-MANAGE-REMOTE-PRCESS-STEP](https://github.com/OT-BUILDPIPER-MARKETPLACE/BP-MANAGE-REMOTE-PRCESS-STEP.git)

```
git clone https://github.com/OT-BUILDPIPER-MARKETPLACE/BP-MANAGE-REMOTE-PRCESS-STEP.git
```
* Build the docker image
```
git submodule init
git submodule update
docker build -t ot/manage-remote-process:0.1

