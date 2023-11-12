# Compute Instance custom metric based Autoscaling using Serverless Functions

In this document we will look at Metric based autoscaling on a custom metric.

About Instance Pools:
In OCI, Instance Pools are used to create and manage multiple compute instances within the same region as a group. We can attach a load balancers to the pool, stop all instances in a pool, increase or decrease the size of the pool (a.k.a scale) and so on. 

Architecture of this solution:

1. As per the architecture, we will use Oracle Linux 8 image and install and configure all the required dependencies using a cloud-init script supplied with this repository.
2. We will need to create a instance configuration and supply a cloud init script when promped under Advance Configuration.
3. The cloud init script will perform management agent installation, installation of required exporters, configuring mgmt agent to scrape prometheus metrics exposed by apache exporters.
4. Using the OCI console we will then define a Alarm rule to be triggered based on the custom metric threshold.
5. We shall create a Serverless Functions app using the OCI console and deploy 2 functions: scale-out and scale-in. Also, configure the required parameters.
6. Create 2 notification topics: One for scale out and the other for scale in. scale-out Function subscribers to scale-out topic and scale-in to scale-in topic.

Flow: When the custom metric 'apache_accesses_total' rate per minute (in short the requests per minute) crosses the threshold mark a trigger would be sent to notifications and the function is invoked. The function does certain checks before scaling.

Before Start:
To start using this procedure, you must have a instance pool created and optionally have attached a load balancer and ensure it is working as expected.

# Create Instance Configuration

