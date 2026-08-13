package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
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

// dynamoTimeout bounds every DynamoDB call so a stalled request cannot pin a
// handler goroutine indefinitely.
const dynamoTimeout = 10 * time.Second

// errNoDynamoDB is returned when the AWS clients were never initialised —
// which happens when AWS_REGION is unset. Callers surface this as a 500
// rather than dereferencing a nil client and panicking.
var errNoDynamoDB = errors.New("DynamoDB client not initialized: set AWS_REGION (and DYNAMODB_ENDPOINT for local development)")

// errAlreadySubmitted signals that a game's score has already been recorded.
var errAlreadySubmitted = errors.New("score already submitted for this game")

// initStorage initializes storage clients based on environment variables
func initStorage() {
	environment := os.Getenv("ENVIRONMENT")
	if environment == "" {
		environment = "development"
	}

	log.Printf("Initializing storage for environment: %s", environment)

	// Log environment variables for debugging
	log.Printf("Environment variables - GAME_SESSIONS_TABLE: %s, DYNAMODB_TABLE: %s, AWS_REGION: %s",
		os.Getenv("GAME_SESSIONS_TABLE"), os.Getenv("DYNAMODB_TABLE"), os.Getenv("AWS_REGION"))

	// Environment-specific initialization
	switch environment {
	case "development":
		log.Println("Development mode: using relaxed settings and verbose logging")
	case "staging":
		log.Println("Staging mode: using production-like settings with enhanced logging")
	case "production":
		log.Println("Production mode: using optimized settings")
	default:
		log.Printf("Unknown environment '%s', using default settings", environment)
	}

	// Initialize AWS clients if configured
	if os.Getenv("AWS_REGION") != "" {
		initAWSClients()
	}

	log.Printf("Storage clients initialized for %s environment", environment)
}

// initAWSClients initializes AWS S3 and DynamoDB clients
func initAWSClients() {
	environment := os.Getenv("ENVIRONMENT")

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

	// Environment-specific client configuration
	switch environment {
	case "development":
		log.Println("AWS clients configured for development (relaxed timeouts)")
	case "staging":
		log.Println("AWS clients configured for staging (production-like timeouts)")
	case "production":
		log.Println("AWS clients configured for production (optimized timeouts)")
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

// DynamoDB Storage Implementation - Save individual entry
func (l *Leaderboard) saveEntryToDynamoDB(ctx context.Context, entry LeaderboardEntry) error {
	if dynamodbClient == nil {
		return errNoDynamoDB
	}

	tableName := os.Getenv("DYNAMODB_TABLE")
	if tableName == "" {
		tableName = "game2048-leaderboard"
	}

	ctx, cancel := context.WithTimeout(ctx, dynamoTimeout)
	defer cancel()

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
		"playerId": &types.AttributeValueMemberS{
			Value: entry.PlayerID,
		},
		"duration": &types.AttributeValueMemberN{
			Value: strconv.Itoa(entry.Duration),
		},
		"moves": &types.AttributeValueMemberN{
			Value: strconv.Itoa(entry.Moves),
		},
	}

	_, err := dynamodbClient.PutItem(ctx, &dynamodb.PutItemInput{
		TableName: aws.String(tableName),
		Item:      item,
	})

	if err != nil {
		log.Printf("Error saving entry to DynamoDB: %v", err)
		return err
	}

	log.Printf("Entry saved to DynamoDB: %s - %d points", entry.Name, entry.Score)
	return nil
}

// Legacy function - now just saves individual entries
func (l *Leaderboard) saveToDynamoDB() {
	// This function is now deprecated - we save entries individually
	log.Printf("saveToDynamoDB called - entries are now saved individually")
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

		// Extract PlayerID
		if playerIdAttr, ok := item["playerId"].(*types.AttributeValueMemberS); ok {
			entry.PlayerID = playerIdAttr.Value
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

		// Extract Duration
		if durationAttr, ok := item["duration"].(*types.AttributeValueMemberN); ok {
			if duration, err := strconv.Atoi(durationAttr.Value); err == nil {
				entry.Duration = duration
			}
		}

		// Extract Moves
		if movesAttr, ok := item["moves"].(*types.AttributeValueMemberN); ok {
			if moves, err := strconv.Atoi(movesAttr.Value); err == nil {
				entry.Moves = moves
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

// clearDynamoDBTable function removed - we now use append-only approach

// sessionsTableName resolves the game-sessions table once, in one place.
func sessionsTableName() string {
	if name := os.Getenv("GAME_SESSIONS_TABLE"); name != "" {
		return name
	}
	return "game2048-sessions-dev"
}

// claimSubmission atomically marks a session as having had its score
// submitted, returning errAlreadySubmitted if another request got there first.
//
// A read-then-write check would let two concurrent submissions for the same
// game both pass, so the guard is a DynamoDB condition expression instead.
// `submitted` is a top-level attribute rather than a field inside the encoded
// game state, so the condition can be evaluated server-side.
func claimSubmission(ctx context.Context, gameID string) error {
	if dynamodbClient == nil {
		return errNoDynamoDB
	}

	ctx, cancel := context.WithTimeout(ctx, dynamoTimeout)
	defer cancel()

	_, err := dynamodbClient.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName: aws.String(sessionsTableName()),
		Key: map[string]types.AttributeValue{
			"id": &types.AttributeValueMemberS{Value: gameID},
		},
		UpdateExpression:    aws.String("SET submitted = :yes"),
		ConditionExpression: aws.String("attribute_exists(id) AND attribute_not_exists(submitted)"),
		ExpressionAttributeValues: map[string]types.AttributeValue{
			":yes": &types.AttributeValueMemberBOOL{Value: true},
		},
	})
	if err != nil {
		var failed *types.ConditionalCheckFailedException
		if errors.As(err, &failed) {
			return errAlreadySubmitted
		}
		return fmt.Errorf("failed to claim submission: %w", err)
	}

	return nil
}

// releaseSubmission undoes a claim, used when the score write that followed it
// failed. Best effort: a failure here only means the player cannot retry.
func releaseSubmission(ctx context.Context, gameID string) {
	if dynamodbClient == nil {
		return
	}

	ctx, cancel := context.WithTimeout(ctx, dynamoTimeout)
	defer cancel()

	if _, err := dynamodbClient.UpdateItem(ctx, &dynamodb.UpdateItemInput{
		TableName: aws.String(sessionsTableName()),
		Key: map[string]types.AttributeValue{
			"id": &types.AttributeValueMemberS{Value: gameID},
		},
		UpdateExpression: aws.String("REMOVE submitted"),
	}); err != nil {
		log.Printf("Failed to release submission claim for game %s: %v", gameID, err)
	}
}

// Game session storage functions
func saveGameSession(ctx context.Context, game *GameState) error {
	if dynamodbClient == nil {
		return errNoDynamoDB
	}

	gameData, err := json.Marshal(game)
	if err != nil {
		log.Printf("Failed to marshal game state for game %s: %v", game.ID, err)
		return fmt.Errorf("failed to marshal game state: %w", err)
	}

	tableName := sessionsTableName()

	log.Printf("Saving game session %s to table %s", game.ID, tableName)

	item := map[string]types.AttributeValue{
		"id":        &types.AttributeValueMemberS{Value: game.ID},
		"gameData":  &types.AttributeValueMemberS{Value: string(gameData)},
		"createdAt": &types.AttributeValueMemberS{Value: game.CreatedAt.Format(time.RFC3339)},
		"ttl":       &types.AttributeValueMemberN{Value: strconv.FormatInt(time.Now().Add(1*time.Hour).Unix(), 10)},
	}

	ctx, cancel := context.WithTimeout(ctx, dynamoTimeout)
	defer cancel()

	_, err = dynamodbClient.PutItem(ctx, &dynamodb.PutItemInput{
		TableName: aws.String(tableName),
		Item:      item,
	})

	if err != nil {
		log.Printf("DynamoDB PutItem error for game %s: %v", game.ID, err)
		return fmt.Errorf("failed to save game session: %w", err)
	}

	log.Printf("Game session saved successfully: %s", game.ID)
	return nil
}

func loadGameSession(ctx context.Context, gameID string) (*GameState, error) {
	if dynamodbClient == nil {
		return nil, errNoDynamoDB
	}

	tableName := sessionsTableName()

	log.Printf("Loading game session %s from table %s", gameID, tableName)

	ctx, cancel := context.WithTimeout(ctx, dynamoTimeout)
	defer cancel()

	result, err := dynamodbClient.GetItem(ctx, &dynamodb.GetItemInput{
		TableName: aws.String(tableName),
		Key: map[string]types.AttributeValue{
			"id": &types.AttributeValueMemberS{Value: gameID},
		},
	})

	if err != nil {
		log.Printf("DynamoDB GetItem error for game %s: %v", gameID, err)
		return nil, fmt.Errorf("failed to load game session: %w", err)
	}

	if result.Item == nil {
		log.Printf("Game session %s not found in DynamoDB table %s", gameID, tableName)
		return nil, fmt.Errorf("game session not found")
	}

	gameDataAttr, ok := result.Item["gameData"]
	if !ok {
		log.Printf("Game data attribute missing for game %s", gameID)
		return nil, fmt.Errorf("game data not found in session")
	}

	gameDataStr, ok := gameDataAttr.(*types.AttributeValueMemberS)
	if !ok {
		log.Printf("Invalid game data format for game %s", gameID)
		return nil, fmt.Errorf("invalid game data format")
	}

	var game GameState
	err = json.Unmarshal([]byte(gameDataStr.Value), &game)
	if err != nil {
		log.Printf("Failed to unmarshal game state for game %s: %v", gameID, err)
		return nil, fmt.Errorf("failed to unmarshal game state: %w", err)
	}

	log.Printf("Successfully loaded game session %s", gameID)
	return &game, nil
}

func deleteGameSession(ctx context.Context, gameID string) error {
	if dynamodbClient == nil {
		return errNoDynamoDB
	}

	tableName := sessionsTableName()

	ctx, cancel := context.WithTimeout(ctx, dynamoTimeout)
	defer cancel()

	_, err := dynamodbClient.DeleteItem(ctx, &dynamodb.DeleteItemInput{
		TableName: aws.String(tableName),
		Key: map[string]types.AttributeValue{
			"id": &types.AttributeValueMemberS{Value: gameID},
		},
	})

	if err != nil {
		return fmt.Errorf("failed to delete game session: %w", err)
	}

	log.Printf("Game session deleted: %s", gameID)
	return nil
}

// Cleanup storage connections (DynamoDB client doesn't need explicit cleanup)
func cleanupStorage() {
	log.Println("Storage cleanup completed")
}
