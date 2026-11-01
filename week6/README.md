# Networking and Ingress

Expose the app via Ingress. 
 
## Week 6 - Tasks

- Install Ingress Controller 
- Create the ingress and frontend resource objects located at `k8s/frontend`
- Check if Ingress Controller is running
- Confirm ingress is routing traffic through the control plane
- On the browser visit `http://notes.127-0-0-1.nip.io` to see the Cloud Native Notes. 
    - Feel free to play with it. You can add, update and delete your notes. 
    - Write about your experience in this bootcamp
    - Share what you are learning with others
- Try to back up you notes 
- Delete the cloud-native-note namespace
- Set up the app again then restore your notes from back up

## Extra Challenges
1. Gateway API is replacing Ingress API.
    - Read up on why Gateway API is a better
    - Can you implement Gateway API on this project?

2. Let's Encrypt provides SSL. 
    - If you have own a domain, it needs to validate your ownership. 
    - Can you implement TLS with Let's Encrypt on your ingress?

3. HERCULEAN TASK

    If you didn't use the kind-config suggested in week 3, you would have to manually expose the ingress to your host machine.

    - Can you build it so that on your browser you can access the api at `notes.local/api` and the frontend at `notes.local`? 

    Note: You may have to make changes to the cluster and edit the `/etc/hosts` file on your machine. Best wishes!

## To Think About
- Why is the LoadBalancer External IP in pending state for the ingress controller?
- Why are we no longer port forwarding?

## Solution Guide

- Install Nginx Ingress Controller

    `kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml`



- Check Ingress routing is ready and working

    `kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s`

    - Expected Result: `pod/ingress-nginx-controller-SOME-RANDOM-CHARACTERS condition met`


- Ingress not on the control plane, patch the existing deployment to pin it to the control-plane:

    `kubectl patch deployment -n ingress-nginx ingress-nginx-controller   --type=merge   -p '{"spec":{"template":{"spec":{"nodeSelector":{"ingress-ready":"true","kubernetes.io/os":"linux"}}}}}'`



## Verify

Run the verification script `./verify-week6.sh`

If your verification score is 100%, you are good to go!

If not, read the report and rectify the error(s).

If you are stucked after several trials, ask for help in the group.


    