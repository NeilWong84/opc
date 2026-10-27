from typing import Annotated
from pydantic import BaseModel, ConfigDict, Field, StringConstraints

Text = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=4000)]


class Input(BaseModel):
    model_config = ConfigDict(extra="forbid")


class VersionInput(Input):
    expected_version: int = Field(ge=1)


class ReasonInput(VersionInput):
    reason: Text
