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
// handler goroutine indefinitely. Loading the leaderboard may paginate, so it
// gets a longer budget than a single-item read or write.
const (
	dynamoTimeout     = 10 * time.Second
	dynamoLoadTimeout = 30 * time.Second
	s3Timeout         = 30 * time.Second
)

// errNoDynamoDB is returned when the AWS clients were never initialised —
// which happens when AWS_REGION is unset. Callers surface this as a 500
// rather than dereferencing a nil client and panicking.
var errNoDynamoDB = errors.New("DynamoDB client not initialized: set AWS_REGION (and DYNAMODB_ENDPOINT for local development)")

// errAlreadySubmitted signals that a game's score has already been recorded.
var errAlreadySubmitted = errors.New("score already submitted for this game")

const (
	// leaderboardIndexName is the GSI used to read scores in rank order.
	leaderboardIndexName = "ScoreIndex"

	// leaderboardPartitionKey / leaderboardPartitionValue form the constant
	// partition every leaderboard entry is written into. DynamoDB can only
	// Query within a single partition, so a shared key is what allows the
	// index to return scores sorted without scanning the whole table.
	leaderboardPartitionKey   = "leaderboard"
	leaderboardPartitionValue = "global"
)

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
//
// S3 holds a JSON snapshot of the whole leaderboard. It serves two purposes:
// a durable backup written after every accepted score, and a read fallback for
// when DynamoDB cannot be reached.

const s3LeaderboardKey = "leaderboard/scores.json"

// s3BackupEnabled reports whether the S3 backup path is configured. Both the
// flag and a bucket are required, so the feature is opt-in.
func s3BackupEnabled() bool {
	return s3Client != nil &&
		os.Getenv("S3_ENABLED") == "true" &&
		os.Getenv("S3_BUCKET") != ""
}

// saveToS3 writes the supplied snapshot to S3.
//
// The caller passes the entries rather than reading l.entries directly, so the
// snapshot is taken under the lock and this function never touches shared state.
func (l *Leaderboard) saveToS3(ctx context.Context, entries []LeaderboardEntry) error {
	if !s3BackupEnabled() {
		return nil
	}

	bucket := os.Getenv("S3_BUCKET")

	data, err := json.Marshal(entries)
	if err != nil {
		return fmt.Errorf("failed to marshal leaderboard for S3: %w", err)
	}

	ctx, cancel := context.WithTimeout(ctx, s3Timeout)
	defer cancel()

	_, err = s3Client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(bucket),
		Key:         aws.String(s3LeaderboardKey),
		Body:        strings.NewReader(string(data)),
		ContentType: aws.String("application/json"),
	})
	if err != nil {
		return fmt.Errorf("failed to write s3://%s/%s: %w", bucket, s3LeaderboardKey, err)
	}

	log.Printf("Leaderboard backed up to s3://%s/%s (%d entries)", bucket, s3LeaderboardKey, len(entries))
	return nil
}

// loadFromS3 restores the leaderboard from the S3 snapshot.
func (l *Leaderboard) loadFromS3() error {
	if s3Client == nil {
		return errors.New("S3 client not initialized")
	}

	bucket := os.Getenv("S3_BUCKET")
	if bucket == "" {
		return errors.New("S3_BUCKET not configured")
	}

	ctx, cancel := context.WithTimeout(context.Background(), s3Timeout)
	defer cancel()

	result, err := s3Client.GetObject(ctx, &s3.GetObjectInput{
		Bucket: aws.String(bucket),
		Key:    aws.String(s3LeaderboardKey),
	})
	if err != nil {
		return fmt.Errorf("failed to read s3://%s/%s: %w", bucket, s3LeaderboardKey, err)
	}
	defer result.Body.Close()

	var entries []LeaderboardEntry
	if err := json.NewDecoder(result.Body).Decode(&entries); err != nil {
		return fmt.Errorf("failed to decode S3 leaderboard snapshot: %w", err)
	}

	l.mu.Lock()
	l.entries = entries
	l.mu.Unlock()

	log.Printf("Leaderboard loaded from S3 fallback: %d entries", len(entries))
	return nil
}

// DynamoDB Storage Implementation - Save individual entry
func (l *Leaderboard) saveEntryToDynamoDB(ctx context.Context, entry LeaderboardEntry) error {
	if dynamodbClient == nil {
		return errNoDynamoDB
	}

	tableName := leaderboardTableName()

	ctx, cancel := context.WithTimeout(ctx, dynamoTimeout)
	defer cancel()

	item := map[string]types.AttributeValue{
		"id": &types.AttributeValueMemberS{
			Value: entry.ID,
		},
		// Constant partition key for the ScoreIndex GSI. A Query requires an
		// equality condition on the partition key, so every leaderboard entry
		// shares one value; `score` is the sort key, which is what makes
		// "top N by score" a Query instead of a full table Scan.
		leaderboardPartitionKey: &types.AttributeValueMemberS{
			Value: leaderboardPartitionValue,
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

// unmarshalEntry converts a DynamoDB item into a LeaderboardEntry.
func unmarshalEntry(item map[string]types.AttributeValue) LeaderboardEntry {
	var entry LeaderboardEntry

	if attr, ok := item["id"].(*types.AttributeValueMemberS); ok {
		entry.ID = attr.Value
	}
	if attr, ok := item["playerId"].(*types.AttributeValueMemberS); ok {
		entry.PlayerID = attr.Value
	}
	if attr, ok := item["name"].(*types.AttributeValueMemberS); ok {
		entry.Name = attr.Value
	}
	if attr, ok := item["score"].(*types.AttributeValueMemberN); ok {
		if score, err := strconv.Atoi(attr.Value); err == nil {
			entry.Score = score
		}
	}
	if attr, ok := item["duration"].(*types.AttributeValueMemberN); ok {
		if duration, err := strconv.Atoi(attr.Value); err == nil {
			entry.Duration = duration
		}
	}
	if attr, ok := item["moves"].(*types.AttributeValueMemberN); ok {
		if moves, err := strconv.Atoi(attr.Value); err == nil {
			entry.Moves = moves
		}
	}
	if attr, ok := item["timestamp"].(*types.AttributeValueMemberS); ok {
		if timestamp, err := time.Parse(time.RFC3339, attr.Value); err == nil {
			entry.Timestamp = timestamp
		}
	}

	return entry
}

// loadFromDynamoDB replaces the in-memory leaderboard from DynamoDB.
//
// This Queries the ScoreIndex GSI rather than Scanning the table. The previous
// Scan read every item in the table on every refresh AND was unpaginated, so it
// silently dropped everything past the first 1 MB of results.
func (l *Leaderboard) loadFromDynamoDB() error {
	if dynamodbClient == nil {
		return errNoDynamoDB
	}

	tableName := leaderboardTableName()

	ctx, cancel := context.WithTimeout(context.Background(), dynamoLoadTimeout)
	defer cancel()

	var entries []LeaderboardEntry
	var startKey map[string]types.AttributeValue

	for {
		result, err := dynamodbClient.Query(ctx, &dynamodb.QueryInput{
			TableName:              aws.String(tableName),
			IndexName:              aws.String(leaderboardIndexName),
			KeyConditionExpression: aws.String("#pk = :pk"),
			ExpressionAttributeNames: map[string]string{
				"#pk": leaderboardPartitionKey,
			},
			ExpressionAttributeValues: map[string]types.AttributeValue{
				":pk": &types.AttributeValueMemberS{Value: leaderboardPartitionValue},
			},
			// Descending, so the highest scores arrive first.
			ScanIndexForward:  aws.Bool(false),
			ExclusiveStartKey: startKey,
		})
		if err != nil {
			log.Printf("Error querying %s: %v", leaderboardIndexName, err)
			return fmt.Errorf("failed to query leaderboard index: %w", err)
		}

		for _, item := range result.Items {
			entries = append(entries, unmarshalEntry(item))
		}

		// Stop once every page has been read, or the in-memory cap is reached.
		startKey = result.LastEvaluatedKey
		if len(startKey) == 0 || len(entries) >= maxCachedEntries {
			break
		}
	}

	if len(entries) > maxCachedEntries {
		entries = entries[:maxCachedEntries]
	}

	l.mu.Lock()
	l.entries = entries
	l.mu.Unlock()

	log.Printf("Leaderboard loaded from DynamoDB (%s): %d entries", leaderboardIndexName, len(entries))
	return nil
}

// leaderboardTableName resolves the leaderboard table once, in one place.
func leaderboardTableName() string {
	if name := os.Getenv("DYNAMODB_TABLE"); name != "" {
		return name
	}
	return "game2048-leaderboard"
}

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
