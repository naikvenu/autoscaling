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
instance_pool_min_size = os.getenv('INSTANCE_POOL_MIN_SIZE', 'not-configured')

def handler(ctx, data: io.BytesIO = None):
    """
    OCI Function Entrypoint
    :param ctx: OCI Function context
    :param data: message payload bytes object
    :return: None
    """

    try:
        print('Fn BEGIN: Apache Scale In Function Invoked')
        log_body = data.getvalue()
        #print('context: ', dir(ctx), 'Body: ',len(log_body), 'body ops:', dir(log_body))
        print("Contents of the body for reference: ", log_body)
        
        # Check if the Configuration values are valid
        try:
          if isinstance(int(instance_pool_min_size), int) :
              print('Valid integer value for INSTANCE_POOL_MIN_SIZE supplied ..')
          else:
              print('Invalid integer value for INSTANCE_POOL_MIN_SIZE supplied ..','min size: ',instance_pool_min_size)
              return response.Response(ctx, response_data={'result': 'No action required'},
                                     headers={"Content-Type": "application/json"})
        except ValueError as err:
            print("Value Error: {}".format(str(err)))
            return response.Response(ctx, response_data={'result': 'No action required'},
                                     headers={"Content-Type": "application/json"})

        # Check if instance_pool size is at its minimum
        if int(instance_pool_min_size) <= 1:
            resp = 'Instance pool Min size supplied is less than or equal to 1. Please provide Min Pool size of 2 and above.'
            print(resp)
            return response.Response(ctx, response_data={'result': resp + ' Not Scaling In'},
                                     headers={"Content-Type": "application/json"})
  
        signer = oci.auth.signers.get_resource_principals_signer()
        compute_management_client = ComputeManagementClient(config={}, signer=signer)
        composite_client = ComputeManagementClientCompositeOperations(compute_management_client)
       
        instance_pool = compute_management_client.get_instance_pool(instance_pool_id).data

        print('Instance pool size: ',instance_pool.size,'Instance pool Name: ',\
            instance_pool.display_name, 'instance pool id: ', instance_pool_id)

        # Check if instance_pool size is below the hard limit of 2
        if instance_pool.size < 2:
            print('The instance pool initial size is hard limited not to be below 2. Please increase the current pool size of ',instance_pool.size, ' to a value greater than 2 and try again..')
            return response.Response(ctx, response_data={'result': 'Not Scaling In'},
                                     headers={"Content-Type": "application/json"})
        
        # Check if instance_pool lifecycle_state is not RUNNING
        if instance_pool.lifecycle_state != "RUNNING":
            print('Instance pool is in state: ', {instance_pool.lifecycle_state},'. No further action.')
            return response.Response(ctx, response_data={'result': 'Instance Pool not in RUNNING state, Not Scaling In'},
                                     headers={"Content-Type": "application/json"})
        
        # Check if instance_pool size is at its maximum
        if instance_pool.size == int(instance_pool_min_size):
            print('Instance pool is already at its minimum size. ')
            return response.Response(ctx, response_data={'result': 'Instance Pool At the Min Size already, Not Scaling In'},
                                     headers={"Content-Type": "application/json"})

        decreased_pool_size = instance_pool.size - 1
        update_details = UpdateInstancePoolDetails(size=decreased_pool_size)
        composite_client.update_instance_pool_and_wait_for_state(instance_pool.id, update_details,
                                                                 wait_for_states=["SCALING"])
        print(update_details)                                                          
        return response.Response(ctx, response_data= {'result':'Scale In initiated, Please check the status for its completion'},
                                 headers={"Content-Type": "application/json"})

    except Exception as err:
        print("Error in handler: {}".format(str(err)))
        raise err