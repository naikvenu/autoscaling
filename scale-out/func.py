## Copyright (c) 2022 Oracle and/or its affiliates.
## All rights reserved. The Universal Permissive License (UPL), Version 1.0 as shown at http://oss.oracle.com/licenses/upl

#Disclaimer:
#This script is provided for experimental purposes only and should not be used in production. 
# It is provided to assist your development or administration efforts and provided “AS IS” and is NOT supported by Oracle Corporation. 
#The script has been tested in a test environment and appears to work as intended. You should always run new scripts on a test environment and validate and modify the same as per your requirements before using on your application environment.
 
import io
import os
from fdk import response
import oci
from oci.core import ComputeManagementClient
from oci.core.models import UpdateInstancePoolDetails
from oci.core import ComputeManagementClientCompositeOperations

# Instance Pool ID
instance_pool_id = os.getenv('INSTANCE_POOL_ID', 'not-configured')
instance_pool_max_size = os.getenv('INSTANCE_POOL_MAX_SIZE', 'not-configured')
instance_pool_increment_size = os.getenv('INSTANCE_POOL_INCREMENT_SIZE', 'not-configured')

def handler(ctx, data: io.BytesIO = None):
    """
    OCI Function Entrypoint
    :param ctx: OCI Function context
    :param data: message payload bytes object
    :return: None
    """

    try:
        print('Fn BEGIN: Apache Scale Out Function Invoked')
        log_body = data.getvalue()

        #print('context: ', dir(ctx), 'Body: ',len(log_body), 'body ops:', dir(log_body))
        print("Contents of the Body for Reference: ", log_body)
        
        # Check if the Configuration values are valid

        try:
          if isinstance(int(instance_pool_max_size), int) and isinstance(int(instance_pool_increment_size), int):
              print('Valid integer values for INSTANCE_POOL_MAX_SIZE and INSTANCE_POOL_INCREMENT_SIZE supplied ..')
          else:
              print('Invalid integer values for INSTANCE_POOL_MAX_SIZE and INSTANCE_POOL_INCREMENT_SIZE supplied ..','max size: ',instance_pool_max_size, ' increment size: ',instance_pool_increment_size)
              return response.Response(ctx, response_data={'result': 'No action required'},
                                     headers={"Content-Type": "application/json"})
        except ValueError as err:
            print("Value Error: {}".format(str(err)))
            return response.Response(ctx, response_data={'result': 'No action required'},
                                     headers={"Content-Type": "application/json"})
    
        if (0 < int(instance_pool_max_size) <= 100):
            print('INSTANCE_POOL_MAX_SIZE is within the acceptable hard limit of 1-100')
        else:
            print('INSTANCE_POOL_MAX_SIZE is not within the acceptable hard limit of 1-100')
            return response.Response(ctx, response_data={'result': 'No action required'},
                                     headers={"Content-Type": "application/json"})
        
        if (0 < int(instance_pool_increment_size) <= 10):
            print('INSTANCE_POOL_INCREMENT_SIZE is within the acceptable hard limit of 1-10')
        else:
            print('INSTANCE_POOL_INCREMENT_SIZE is not within the acceptable hard limit of 1-10')
            return response.Response(ctx, response_data={'result': 'No action required'},
                                     headers={"Content-Type": "application/json"})
             
        signer = oci.auth.signers.get_resource_principals_signer()
        compute_management_client = ComputeManagementClient(config={}, signer=signer)
        composite_client = ComputeManagementClientCompositeOperations(compute_management_client)
       
        instance_pool = compute_management_client.get_instance_pool(instance_pool_id).data

        print('Instance Pool Size: ',instance_pool.size,'Instance Pool Name: ',\
            instance_pool.display_name, 'Instance Pool Id: ', instance_pool_id)
        
        
        # Check if instance_pool size is at its maximum
        if instance_pool.size == int(instance_pool_max_size):
            print('Instance pool is already at its maximum size. Please increase the pool max size to handle the load.')
            return response.Response(ctx, response_data={'result': 'Instance Pool At the Max Size already, Not Scaling'},
                                     headers={"Content-Type": "application/json"})

        # Check if instance_pool lifecycle_state is not RUNNING
        if instance_pool.lifecycle_state != "RUNNING":
            print('Instance pool is in state: ', {instance_pool.lifecycle_state},'. No further action.')
            return response.Response(ctx, response_data={'result': 'Instance Pool not in RUNNING state, Not Scaling'},
                                     headers={"Content-Type": "application/json"})
        
        if (instance_pool.size + int(instance_pool_increment_size)) > int(instance_pool_max_size):
            print('Instance pool size: ',instance_pool.size,'+', instance_pool_increment_size,' is greater than max pool limit ',instance_pool_max_size)
            print('Just incrementing the pool size by 1')
            increased_pool_size = instance_pool.size + 1
        else:
            print('Incrementing the pool size by ',int(instance_pool_increment_size))
            increased_pool_size = instance_pool.size + int(instance_pool_increment_size)
            
        update_details = UpdateInstancePoolDetails(size=increased_pool_size)
        composite_client.update_instance_pool_and_wait_for_state(instance_pool.id, update_details,
                                                                 wait_for_states=["SCALING"])
        print(update_details)                                                          
        return response.Response(ctx, response_data= {'result':'Scale Out initiated, Please check the status for its completion'},
                                 headers={"Content-Type": "application/json"})

    except Exception as err:
        print("Error in handler: {}".format(str(err)))
        raise err