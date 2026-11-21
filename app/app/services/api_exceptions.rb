# JSON fallback for exceptions raised outside controller rescue handlers.
class ApiExceptions
  def self.call(env)
    exception = env.fetch('action_dispatch.exception')
    status = ActionDispatch::ExceptionWrapper.new(nil, exception).status_code
    code = status == 500 ? 'internal_error' : 'request_error'
    message = status == 500 ? 'An unexpected error occurred.' : 'The request could not be processed.'
    body = JSON.generate(error: { code: code, message: message })
    [status, { 'content-type' => 'application/json', 'cache-control' => 'no-store' }, [body]]
  end
end
