# Web App with Terraform and AWS

The purpose of this repository is to demonstrate how to create a web app that does not store data on its local server instance but rather in a separate database. This is the typical format for cloud operation: computing is separate to storage so that it can be scaled automatically; storage is separate so that scaling does not impact the persistance of data. 

In this case, the computing part is performed with AWS Elastic Compute Cloud EC2 instances. An instance is created and a user script run to install docker, pull a docker image from an S3 bucket, and start a container from that image. The persistence of these instances is controlled by an autoscaler, and access to them is controlled by a load balancer. All of this is provisioned by Terraform, an Infrastructure as Code (IaC) tool that 

This repo contains the basic scripts to use Terraform to deploy a Django web app that uses AWS RDS for its remote data store. You will first need to package the app as a Docker image From there it can be deployed to an EC2 instance where it will be connected to an RDS server.

The repo has the following structure:

```
/
├── app/
├── terraform/
└── README.md
```

The `app/` directory contains the source code for the Django application. The `terraform/` directory contains terraform files to provision your infrastructure to the cloud.

The app is copied from Mozilla's Django tutorial. It is a simple site that acts as a portal for a library. It keeps track of a book inventory, the library users, what books are checked out, and which user checked them out. All of this data is stored in a separate database.

## Building and Packaging the App
There is a Dockerfile which builds an image which can be used to provision containers. The web server that will run in the final docker containers will run on port 8000. This is mapped to port 80 on the EC2 instance which allows web traffic.

In order to run this web app, you will need to build the image. Close the Dockerfile and build the image using the following command (with your own tag):
```sh
docker build -t <insert your tag>
```
Save the image using the `docker save -o <filename>.tar` command in the root directory of this project. Take note of the filename as this needs to be entered in the `terraform/variables.tf` file.

## Terraform
### main.tf
* Provider: 'aws' from your installation of terraform 
* VPC and subnets: set as default which uses the existing configuration in your AWS account
* S3: a bucket with block access to store the image and distribute it to new EC2 app server instances
* Security Groups: there are two security groups, one for the RDS instance and another for the app server run on an EC2 instance. Notice the app server has standard http and ssh access while the RDS security group has a pipe directly to the app server security group. This allows traffic only from an app server instance.
* RDS Instance: engine is Postgres v12.9 run on a t2.micro free tier instance
* Load-balancer: simple LB with listener that returns a default 404 page if page not found
* Auto-scaling group: a simple auto-scaler with min size of 1 and max of 10

### outputs.tf
Configured to print the IP address for the configured load balancer and the URL of your database if you need to debug it or want to check it out. Note that because of the tunnel you set in the security groups, you can only connect to the RDS database from an EC2 instance. You can find an EC2 instance using your AWS portal and ssh in using the public IPV4 address.

### Apply
Make sure to run all terraform commands from the `../terraform` directory in this project. Run `terraform init` to pull the provider to the root directory of this project. Optionally also run `terraform validate` and `terraform fmt` to ensure that your code is correct. Because the database username and password have no default in `terraform/variables.tf` file, you will be asked for the database username and password every time you run `terraform apply`; if you want to avoid this, set the environment variables:
```sh
export TF_VAR_db_username="<db username>"
export TF_VAR_db_username="<db password>"
```
Finally, run `terraform apply` to provision your configuration to the cloud.

## Access
In your browser, enter the public address for the load balancer and you should see the webpage. If you want to perform admin duties like accessing the database, go to `<IP address>/admin` and create an account. You can add some entries in the various tables through the admin page and view them on the main page. All of the data that you enter is stored in the RDS database which can be viewed through your AWS portal.