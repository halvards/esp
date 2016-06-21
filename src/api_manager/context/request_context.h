/*
 * Copyright (C) Endpoints Server Proxy Authors
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */
#ifndef API_MANAGER_CONTEXT_REQUEST_CONTEXT_H_
#define API_MANAGER_CONTEXT_REQUEST_CONTEXT_H_

#include <memory>

#include "include/api_manager/request.h"
#include "include/api_manager/response.h"
#include "src/api_manager/cloud_trace/cloud_trace.h"
#include "src/api_manager/context/service_context.h"
#include "src/api_manager/method.h"
#include "src/api_manager/service_control/info.h"

namespace google {
namespace api_manager {
namespace context {

// Stores request related data to be used by CheckHandler.
class RequestContext {
 public:
  RequestContext(std::shared_ptr<context::ServiceContext> service_context,
                 std::unique_ptr<Request> request);

  // Get the ApiManagerImpl object.
  context::ServiceContext *service_context() { return service_context_.get(); }

  // Get the request object.
  Request *request() { return request_.get(); }

  // Get the method info.
  const MethodInfo *method() const { return method_call_.method_info; }

  // Get the method info.
  const MethodCallInfo *method_call() const { return &method_call_; }

  // Get the api key.
  const std::string &api_key() const { return api_key_; }

  // set the final check continuation callback function.
  void set_check_continuation(
      std::function<void(utils::Status status)> continuation) {
    check_continuation_ = continuation;
  }

  // set the is_api_key_valid field.
  void set_is_api_key_valid(bool b) { is_api_key_valid_ = b; }

  // Fill CheckRequestInfo
  void FillCheckRequestInfo(service_control::CheckRequestInfo *info);

  // Fill ReportRequestInfo
  void FillReportRequestInfo(Response *response,
                             service_control::ReportRequestInfo *info);

  // Complete check.
  void CompleteCheck(utils::Status status);

  // Sets auth issuer to request context.
  void set_auth_issuer(const std::string &issuer) { auth_issuer_ = issuer; }

  // Sets auth audience to request context.
  void set_auth_audience(const std::string &audience) {
    auth_audience_ = audience;
  }

  cloud_trace::CloudTrace *cloud_trace() { return cloud_trace_.get(); }

 private:
  // Fill OperationInfo
  void FillOperationInfo(service_control::OperationInfo *info);

  // Fill location info.
  void FillLocation(service_control::ReportRequestInfo *info);

  // Fill compute platform information.
  void FillComputePlatform(service_control::ReportRequestInfo *info);

  // Fill log message.
  void FillLogMessage(service_control::ReportRequestInfo *info);

  // Extracts api-key
  void ExtractApiKey();

  // The ApiManagerImpl object.
  std::shared_ptr<context::ServiceContext> service_context_;

  // request object to encapsulate request data.
  std::unique_ptr<Request> request_;

  // The final check continuation
  std::function<void(utils::Status status)> check_continuation_;

  // The method info from service config.
  MethodCallInfo method_call_;

  // Randomly generated UUID for each request, passed to service control
  // Check and Report calls.
  std::string operation_id_;

  // api key.
  std::string api_key_;

  // TODO: change default to false.
  // If the request has a valid api key. Used only for Report call.
  // Initialized to true, and will be set to false if it can be confirmed
  // by the check call from the service control server.
  bool is_api_key_valid_;

  // Needed by both Check() and Report, extract it once and store it here.
  std::string http_referer_;

  // auth_issuer. It will be used in service control Report().
  std::string auth_issuer_;

  // auth_audience. It will be used in service control Report().
  std::string auth_audience_;

  // Used by cloud tracing
  std::unique_ptr<cloud_trace::CloudTrace> cloud_trace_;
};

}  // namespace context
}  // namespace api_manager
}  // namespace google

#endif  // API_MANAGER_CONTEXT_REQUEST_CONTEXT_H_