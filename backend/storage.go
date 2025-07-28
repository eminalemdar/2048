package main

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

var (
	s3Client       *s3.Client
	dynamodbClient *dynamodb.Client
)

// initStorage initializes storage clients based on environment variables
func initStorage() {
	// Initialize AWS clients if configured
	if os.Getenv("AWS_REGION") != "" {
		initAWSClients()
	}

	log.Println("Storage clients initialized")
}

// initAWSClients initializes AWS S3 and DynamoDB clients
func initAWSClients() {
	cfg, err := config.LoadDefaultConfig(context.TODO(),
		config.WithRegion(os.Getenv("AWS_REGION")),
	)
	if err != nil {
		log.Printf("Error loading AWS config: %v", err)
		return
	}

	s3Client = s3.NewFromConfig(cfg)

	// Check if we're using DynamoDB Local for development
	if endpoint := os.Getenv("DYNAMODB_ENDPOINT"); endpoint != "" {
		dynamodbClient = dynamodb.NewFromConfig(cfg, func(o *dynamodb.Options) {
			o.BaseEndpoint = aws.String(endpoint)
		})
		log.Printf("DynamoDB client initialized with local endpoint: %s", endpoint)
	} else {
		dynamodbClient = dynamodb.NewFromConfig(cfg)
		log.Println("DynamoDB client initialized for AWS")
	}

	log.Println("AWS clients initialized (S3 and DynamoDB)")
}

// S3 Storage Implementation
func (l *Leaderboard) saveToS3() {
	if s3Client == nil {
		return
	}

	bucket := os.Getenv("S3_BUCKET")
	if bucket == "" {
		log.Println("S3_BUCKET not configured")
		return
	}

	data, err := json.Marshal(l.entries)
	if err != nil {
		log.Printf("Error marshaling leaderboard for S3: %v", err)
		return
	}

	key := "leaderboard/scores.json"
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	_, err = s3Client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(bucket),
		Key:         aws.String(key),
		Body:        strings.NewReader(string(data)),
		ContentType: aws.String("application/json"),
	})

	if err != nil {
		log.Printf("Error saving to S3: %v", err)
		return
	}

	log.Printf("Leaderboard saved to S3: s3://%s/%s", bucket, key)
}

func (l *Leaderboard) loadFromS3() {
	if s3Client == nil {
		return
	}

	bucket := os.Getenv("S3_BUCKET")
	if bucket == "" {
		return
	}

	key := "leaderboard/scores.json"
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	result, err := s3Client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(key),
	})

	if err != nil {
		log.Printf("Error loading from S3: %v", err)
		return
	}
	defer result.Body.Close()

	var entries []LeaderboardEntry
	err = json.NewDecoder(result.Body).Decode(&entries)
	if err != nil {
		log.Printf("Error decoding S3 data: %v", err)
		return
	}

	l.mu.Lock()
	l.entries = entries
	l.mu.Unlock()

	log.Printf("Leaderboard loaded from S3: %d entries", len(entries))
}

// DynamoDB Storage Implementation
func (l *Leaderboard) saveToDynamoDB() {
	if dynamodbClient == nil {
		return
	}

	tableName := os.Getenv("DYNAMODB_TABLE")
	if tableName == "" {
		tableName = "game2048-leaderboard"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// First, clear existing data by scanning and deleting all items
	l.clearDynamoDBTable(ctx, tableName)

	// Insert new entries
	for _, entry := range l.entries {
		item := map[string]types.AttributeValue{
			"id": &types.AttributeValueMemberS{
				Value: entry.ID,
			},
			"name": &types.AttributeValueMemberS{
				Value: entry.Name,
			},
			"score": &types.AttributeValueMemberN{
				Value: strconv.Itoa(entry.Score),
			},
			"timestamp": &types.AttributeValueMemberS{
				Value: entry.Timestamp.Format(time.RFC3339),
			},
		}

		_, err := dynamodbClient.PutItem(ctx, &dynamodb.PutItemInput{
			TableName: aws.String(tableName),
			Item:      item,
		})

		if err != nil {
			log.Printf("Error saving entry to DynamoDB: %v", err)
			continue
		}
	}

	log.Printf("Leaderboard saved to DynamoDB: %d entries", len(l.entries))
}

func (l *Leaderboard) loadFromDynamoDB() {
	if dynamodbClient == nil {
		return
	}

	tableName := os.Getenv("DYNAMODB_TABLE")
	if tableName == "" {
		tableName = "game2048-leaderboard"
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Scan all items from the table
	result, err := dynamodbClient.Scan(ctx, &dynamodb.ScanInput{
		TableName: aws.String(tableName),
	})

	if err != nil {
		log.Printf("Error loading from DynamoDB: %v", err)
		return
	}

	var entries []LeaderboardEntry
	for _, item := range result.Items {
		var entry LeaderboardEntry

		// Extract ID
		if idAttr, ok := item["id"].(*types.AttributeValueMemberS); ok {
			entry.ID = idAttr.Value
		}

		// Extract Name
		if nameAttr, ok := item["name"].(*types.AttributeValueMemberS); ok {
			entry.Name = nameAttr.Value
		}

		// Extract Score
		if scoreAttr, ok := item["score"].(*types.AttributeValueMemberN); ok {
			if score, err := strconv.Atoi(scoreAttr.Value); err == nil {
				entry.Score = score
			}
		}

		// Extract Timestamp
		if timestampAttr, ok := item["timestamp"].(*types.AttributeValueMemberS); ok {
			if timestamp, err := time.Parse(time.RFC3339, timestampAttr.Value); err == nil {
				entry.Timestamp = timestamp
			}
		}

		entries = append(entries, entry)
	}

	l.mu.Lock()
	l.entries = entries
	l.mu.Unlock()

	log.Printf("Leaderboard loaded from DynamoDB: %d entries", len(entries))
}

// Helper function to clear DynamoDB table
func (l *Leaderboard) clearDynamoDBTable(ctx context.Context, tableName string) {
	// Scan to get all items
	result, err := dynamodbClient.Scan(ctx, &dynamodb.ScanInput{
		TableName:            aws.String(tableName),
		ProjectionExpression: aws.String("id"), // Only get the key
	})

	if err != nil {
		log.Printf("Error scanning DynamoDB table for cleanup: %v", err)
		return
	}

	// Delete each item
	for _, item := range result.Items {
		if idAttr, ok := item["id"].(*types.AttributeValueMemberS); ok {
			_, err := dynamodbClient.DeleteItem(ctx, &dynamodb.DeleteItemInput{
				TableName: aws.String(tableName),
				Key: map[string]types.AttributeValue{
					"id": &types.AttributeValueMemberS{Value: idAttr.Value},
				},
			})
			if err != nil {
				log.Printf("Error deleting item from DynamoDB: %v", err)
			}
		}
	}
}

// Cleanup storage connections (DynamoDB client doesn't need explicit cleanup)
func cleanupStorage() {
	log.Println("Storage cleanup completed")
}
