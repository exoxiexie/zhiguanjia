"""统一错误结构：{"error": {"code": "...", "message": "..."}}

好处：App 端只需判断 error.code，不必解析中文文案或依赖 HTTP 码语义。
"""

from fastapi import HTTPException


def api_error(status_code: int, code: str, message: str) -> HTTPException:
    return HTTPException(status_code=status_code, detail={"code": code, "message": message})
