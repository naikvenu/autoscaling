# Compute Instance custom metric based Autoscaling using Serverless Functions

In OCI instance pools are used to create and manage multiple compute instances within the same region as a group. We can attach a load balancers to the pool, stop all instances in a pool and so on. This document focuses on instances part of instance pool and how can we scale them based on certain conditions.

To start using this procedure, you must have a instance pool created and optionally have attached a load balancer and ensure it is working as expected.
