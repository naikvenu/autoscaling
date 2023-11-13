# Compute Instance custom metric based Autoscaling using Serverless Functions

In this document we will look at Metric based autoscaling on custom metrics.

About Instance Pools:
In OCI, Instance Pools are used to create and manage multiple compute instances within the same region as a group. We can attach a load balancers to the pool, stop all instances in a pool, increase or decrease the size of the pool (a.k.a scale) and so on. 

Architecture of this solution:

1. As per the architecture, we will use Oracle Linux 8 image and install and configure all the required dependencies using a cloud-init script supplied with this repository.
2. We will need to create a instance configuration and supply a cloud init script when promped under Advance Configuration options.
3. The cloud init script will perform management agent installation, installation of required exporters, configuring mgmt agent to scrape prometheus metrics exposed by exporters.
4. Using the OCI console we will then define a Alarm rule to be triggered based on the custom metric threshold.
5. We shall create a Serverless Functions app using the OCI console and deploy 2 functions: scale-out and scale-in. Also, configure the required parameters.
6. Create 2 notification topics: One for scale out and the other for scale in. scale-out Function subscribers to scale-out topic and scale-in to scale-in topic.

Flow: When the custom metric 'apache_accesses_total' rate per minute (in short the requests per minute) crosses the threshold mark a trigger would be sent to notifications and the function is invoked. The function does required checks before scaling.

Before Start, you must have a instance pool created and optionally have attached a load balancer and ensure it is working as expected. The following steps walks through the details:

# Create Instance Configuration

Firstly, create a instance configuration using the below steps:

https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/creatinginstanceconfig.htm
Note: Select OL8 as your image, add your ssh keys and click advanced options to add apache-init.sh cloud init script. apache-init.sh is found in this repository.

# Create Instance Pool

Create an instance pool using the instance configuration created in the previous step. Refer the below document if required 
https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/creatinginstancepool.htm

Select a size of 2 as this is minimum required by the scaling function.

# Attach a OCI Load Balancer

Follow the steps provided here:
https://docs.oracle.com/en-us/iaas/Content/Compute/Tasks/updatinginstancepool_topic-To_attach_a_load_balancer_to_an_instance_pool.htm

# Access the Application

On your browser access the application using load balancer or instance public IP http://<Load-Balancer-IP>

# Deploy OCI Serverless Function

a. Create Application:
    In the Console, open the navigation menu and click Developer Services. Under Functions, click Applications. and Create Application.
    https://docs.oracle.com/en-us/iaas/Content/Functions/Tasks/functionscreatingapps.htm
    Follow the instructions on the screen. Use Generic_X86 as the shape of the Fn.
    
    Click on getting started tab and follow 'Setup fn CLI on Cloud Shell'.
    Open Cloud shell and perform the steps as per the instructions. 
    
    Clone or Copy this repository from cloud shell.
    
    $ cd scale-out
    
    $ fn list apps
    
    $ fn -v deploy --app <app-name>
    
b. Configure Application

    INSTANCE_POOL_INCREMENT_SIZE 2
    INSTANCE_POOL_MIN_SIZE	1	
    INSTANCE_POOL_MAX_SIZE	10
    INSTANCE_POOL_ID	<pool-id>

# Create Notifications Topic

  a. scale-out topic
    
    OCI console -> OCI Notifications -> Create scale-out topic
    
    Add Subscription as scale-out Function created from previous step.

  b. scale-in topic
    
    OCI console -> OCI Notifications -> Create scale-in topic
    
    Add Subscription as scale-in Function created from previous step.

# Create Alarm Definitions

At this point you shall see the metrics flowing through to OCI monitoring. Check the following:

OCI console -> OCI monitoring -> Metrics Explorer -> apache_mod_stats (namespace) -> apache_accesses_total (metric) and check if you see the data points.

If yes, then proceed to creating Alarm definitions.

1. Scale-out Alarm:
   a. OCI console -> OCI monitoring -> Create scale-out Alarm 
   b. Choose apache_mod_stats (namespace) -> apache_accesses_total (metric) -> Statistics as rate of change
   c. Choose a threshold value of 500 for the testing
   d. Select target as scale-out notification topic

3. Scale-out Alarm:
   a. OCI console -> OCI monitoring -> Create scale-out Alarm 
   b. Choose apache_mod_stats (namespace) -> apache_accesses_total (metric) -> Statistics as rate of change
   c. Choose a threshold value of 100 for the testing
   d. Select target as scale-in notification topic


# Test Scaling

For this create another instance and call it load generator
$ sudo dnf install -y httpd

We can use apache benchmark tool to introduce some load:

$ ab -n 5000 -c 50 http://152.69.172.0:80/index.php 

-n indicates the number of requests
-c is the concurrency



