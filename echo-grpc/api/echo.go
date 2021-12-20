// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package api

import (
	"context"
	"log"
	"os"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/metadata"
)

// Server for the Echo gRPC API
type Server struct{}

// Echo the content of the request
func (s *Server) Echo(ctx context.Context, in *EchoRequest) (*EchoResponse, error) {
	log.Printf("Handling Echo request [%v] with context %v", in, ctx)
	hostname, err := os.Hostname()
	if err != nil {
		log.Printf("Unable to get hostname %v", err)
		hostname = ""
	}

	time.Sleep(2 * time.Second)

	grpc.SendHeader(ctx, metadata.Pairs("hostname", hostname))
	return &EchoResponse{Content: in.Content}, nil
}
