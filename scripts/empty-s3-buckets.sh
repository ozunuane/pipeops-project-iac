#!/bin/bash
# Empty S3 buckets without deleting them

echo "=== Emptying S3 buckets ==="

# Find all buckets with pipeops or terraform in the name
buckets=$(aws s3api list-buckets --query 'Buckets[?contains(Name, `pipeops`) || contains(Name, `terraform`)].Name' --output text 2>/dev/null)

if [ ! -z "$buckets" ]; then
    for bucket in $buckets; do
        echo "Emptying bucket: $bucket"
        aws s3 rm "s3://$bucket" --recursive 2>&1 | tail -3 || echo "  Error or already empty"
    done
else
    echo "No buckets found to empty"
fi

echo "=== Done ==="
