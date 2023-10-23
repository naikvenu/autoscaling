
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
instance_pool_max_size = os.getenv('INSTANCE_POOL_MAX_SIZE', 'not-configured')

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
        
        if instance_pool_min_size == 'not-configured' and instance_pool_max_size == 'not-configured':
            print('Both INSTANCE_POOL_MIN_SIZE and INSTANCE_POOL_MAX_SIZE are not configured. Nothing to do.')
            return response.Response(ctx, response_data={'result': 'No action required'},
                                     headers={"Content-Type": "application/json"})

        
        signer = oci.auth.signers.get_resource_principals_signer()
        compute_management_client = ComputeManagementClient(config={}, signer=signer)
        composite_client = ComputeManagementClientCompositeOperations(compute_management_client)
       
        instance_pool = compute_management_client.get_instance_pool(instance_pool_id).data

        print('Instance pool size: ',instance_pool.size,'Instance pool Name: ',\
            instance_pool.display_name, 'instance pool id: ', instance_pool_id)
        
         # Check if instance_pool size is at its minimum and maximum
        if (int(instance_pool_min_size) <= 1) and (int(instance_pool_max_size) >= 50):
            resp = 'Either Instance pool Min size is less than 1 Or Max Size is greater than 50.'
            print(resp)
            return response.Response(ctx, response_data={'result': resp + ' Not Scaling In'},
                                     headers={"Content-Type": "application/json"})
  
        
        # Check if instance_pool lifecycle_state is not RUNNING
        if instance_pool.lifecycle_state != "RUNNING":
            print('Instance pool is in state: ', {instance_pool.lifecycle_state},'. No further action.')
            return response.Response(ctx, response_data={'result': 'Instance Pool not in RUNNING state, Not Scaling In'},
                                     headers={"Content-Type": "application/json"})
        
        # Check if instance_pool size is at its maximum
        if instance_pool.size == int(instance_pool_min_size):
            print('Instance pool is already at its minimum size. ')
            return response.Response(ctx, response_data={'result': 'Instance Pool At the Min Size already, Not Scaling'},
                                     headers={"Content-Type": "application/json"})
    
        if instance_pool.size == 1:
            print('Instance pool size is 1 which is the minimum, Do Nothing .. ')
            return response.Response(ctx, response_data={'result': 'Instance pool size is 1, Do Nothing'},
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




