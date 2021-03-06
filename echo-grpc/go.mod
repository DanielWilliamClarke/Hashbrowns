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

// https://github.com/golang/go/wiki/Modules

module github.com/GoogleCloudPlatform/grpc-gke-nlb-tutorial/echo-grpc

go 1.12

require (
	github.com/golang/protobuf v1.4.1
	golang.org/x/net v0.0.0-20190522155817-f3200d17e092 // indirect
	google.golang.org/grpc v1.27.0
	google.golang.org/protobuf v1.25.0
)
