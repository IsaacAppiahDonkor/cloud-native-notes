# Basic Troubleshooting

Learn how to find information needed for troubleshooting. You have used some of this commands before. Let's dive deeper. 
 
## Week 5 - Tasks

- `kubectl get` 
- `kubectl describe`
- `kubectl logs`
- `kubectl events` 
- `kubectl exec` 
- `kubectl help`
- `kubectl explain`


## Extra Challenges
1. Deploy a pod with a deliberate typo in the image name, then use `kubectl describe` and `kubectl events` to identify the exact error. Screenshot both outputs and explain the difference on the group.
2. Explore other `kubectl` commands
3. Try `kubectl <command> --help` to gain further insight

## To Think About

- How helpful is the documentation on the CLI?


## Solution Guide
1. What's the pod state?

`kubectl get pods -n cloud-native-notes`

Look at: STATUS column (Pending, ContainerCreating, CrashLoopBackOff, Error, Running)

2. What does the cluster say?

`kubectl describe pod -n cloud-native-notes <pod-name>`

Look at: Events section at the bottom (this is where the real story is)

3. What does the app say?

`kubectl logs -n cloud-native-notes <pod-name> `

`kubectl logs  n cloud-native-notes <pod-name> --previous`    # For crashed pods

4. Get inside the pod

`kubectl exec -it -n cloud-native-notes <pod-name> -- /bin/sh`

Test: curl localhost:3000/health, ls -la /data, env | grep REDIS

5. What's happening in the cluster?

`kubectl events -n cloud-native-notes --sort-by='.lastTimestamp'`

Look at: What happened recently? Scheduling? Image pulls? Volume mounts?


## Verify

Run the verification script ./verify-week5.sh

If your verification score is 100%, you are good to go!

If not, read the report and rectify the error(s).

If you are stucked after several trials, ask for help in the group.


## Notes
This is a time to take some rest and just reflect on your progress so far. 

Help others who are having difficulties and share your knowledge. 

Connect with fellow learners. Maybe your next co-founder is in this group.

Best Wishes!
