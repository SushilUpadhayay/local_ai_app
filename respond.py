"""
Call Response

Input (Last Sumamry + Latest Question)

Calculate: Query+Answer(done), Product_Identify(static), Ongoing_or_first_convo, Senti(done), Lang(done), Personality(done)

Calculate: Refine_Reply
"""

from pydantic import BaseModel
from typing import Optional, List, Dict, Literal
from langchain_core.runnables import RunnableMap
from src.models.summary import SummaryModel
from src.helper.logger import setup_new_logging
from src.v2.dashboard.cta.models import CTAType
import streamlit as st

from llama_index.core.memory import ChatSummaryMemoryBuffer
from llama_index.core.llms import ChatMessage

from .gen_query_n_reply import generate_answer_from_query #generate_query
# from src.streamlitdemo.chatdemo.identify_product import identify_product

from src.v3.product_related.identify_product_v2 import identify_product
from .senti_lang import detect_language # , sentiment_classification
# from src.helper.resolve_llm import resolve_llm
# from .personaliy import generate_personality
# from .contextualize import contextualize_messages
# from .reply import refine_reply
# from .phrases_to_avoid import phrases_to_avoid
# from .spin_states import gather_information_for_cur_state, all_requirements_fullfilled
from .simulate_tools import (
    # get_available_booking_dates,
    # book_date,
    # get_current_date,
    # check_booking_status,
    create_issue_tickets,
    # get_ticket_status,
    initial_address_information,
    handle_booking,
)

# from .track_time import time_it
import openai
import json  # Add this import at the top
import asyncio

logger = setup_new_logging(__name__)

class MsgRequest(BaseModel):
    customer_id: Optional[str] = None
    chat_history_format: Literal["role_content", "role_data"] = "role_content"
    chat_history: Optional[List] = None
    message: Optional[str] = None
    message_media_values: Optional[str] = None
    image_process_metadata: Optional[Dict] = None

    current_spin_state: Optional[str] = None
    next_spin_state: Optional[str] = None
    info_gathering: Optional[dict] = None

    previous_summary: Optional[str | list] = None
    spin_states: Optional[Dict] = None
    channel: Optional[str] = None


    #let's just use message and user_id from this

    @property
    def json_data_with_fields_str_formatted(self) -> str:
        gathered_info = self.info_gathering
        gathered_info.pop("name")
        return str(gathered_info)
    def set_new_summary(self, summary_str):
        self.previous_summary = summary_str

# @time_it
# def generate_response(req: MsgRequest) -> str:
#     response_chain = RunnableMap({
#         "query_answer":lambda x: generate_answer_from_query(query=generate_query(x)),
#         # "identifed_product": identify_product,
#         # "sentiment": sentiment_classification,
#         "language": detect_language,
#         # "personality": generate_personality,

#         # "contextualize": contextualize_messages,

#         # to carry over
#         "summary_str": lambda x: x["summary_str"],
#         "latest_message_str": lambda x: x["latest_message_str"],

#         "current_spin_state": lambda x: x["current_spin_state"],
#         "next_spin_state": lambda x: x["next_spin_state"],
#         "json_data_with_fields_str_formatted": lambda x: x["json_data_with_fields_str_formatted"],
#         "spin_states": lambda x: x["spin_states"]
#     }) | {
#         "refined_reply": refine_reply,
#         "prev_values": lambda x: x
#     }


#     response = response_chain.invoke({
#         "latest_message_str": req.message,
#         "summary_str": req.previous_summary,
#         "current_spin_state": req.current_spin_state,
#         "next_spin_state": req.next_spin_state,
#         "json_data_with_fields_str_formatted": req.json_data_with_fields_str_formatted,
#         "spin_states": req.spin_states
#     })


#     # print(response)
#     # run this is background in a seperate thread

#     calculate_summary("This is a New Conversation", req.message, response.get("refined_reply"))

#     # also save the contextualize as cache

#     return response.get("refined_reply")


# @time_it
# def calculate_summary(prev_summary, user_message,ai_response) -> str:

#     prompt=db["prompt"].find_one({"name":"summary_prompt"})["text"]

#     chat_history = [
#         ChatMessage(role="system", content="Summary of the Conversation: "+prev_summary),
#         ChatMessage(role="user", content=user_message),
#         ChatMessage(role="assistant", content=ai_response)
#     ]

#     memory = ChatSummaryMemoryBuffer.from_defaults(
#         chat_history=chat_history,
#         llm=resolve_llm(model_name="models/gemini-2.0-flash"),
#         token_limit=1,  # Adjusted for meaningful summaries
#         summarize_prompt=prompt,
#         # tokenizer_fn=tokenizer_fn,
#     )

#     # Log successful processing
#     summary_ = memory.get()
#     # print(summary_)
#     return summary_[0].content


# @time_it
async def generate_response_openai(req: MsgRequest, SYS_PROMPT, qd_client, current_user) -> str:
    print("chatdemo response openai")
    SYSTEM_PROMPT = SYS_PROMPT["text"]

    source_nodes = []
    tool_calls = None
    tool_calls_results = []

    DETECT_LANGUAGE_PROMPT = current_user.db.prompt.find_one({"name":"language_detection"})
    IDENTIFY_PRODUCT_PROMPT = current_user.db.prompt.find_one({"name":"identify_product"})

    identified_product,prod_usage=identify_product({"latest_message_str": req.message, "prompt": IDENTIFY_PRODUCT_PROMPT}, current_user=current_user)
    language_data = {"latest_message_str": req.message, "prompt": DETECT_LANGUAGE_PROMPT}
    language_result = detect_language(language_data, current_user=current_user)

    # Extract detected language safely
    language = language_result["result"].get("detected_language", None)
    lang_usage = language_result.get("usage", {})
    
    # Format system prompt
    SYSTEM_PROMPT = SYSTEM_PROMPT.format(
        # answer=data["query_answer"].get("reply"),
        identified_product=identified_product,
        language=language,
        # additional_context=data.get("additional_context", ""),
        response_mode_str="Provide a detailed and explained answer in a couple of sentences."
    )

    env = current_user.db.settings.find_one({"name": "env"})
    API_KEYS = env.get("config")
    openai_client = openai.OpenAI(api_key=API_KEYS.get("OPENAI_API_KEY"))

    # print(SYSTEM_PROMPT)

    # Initialize messages list
    messages = [{"role": "system", "content": SYSTEM_PROMPT}]
    if isinstance(req.previous_summary, list):
        messages.extend(req.previous_summary)
    messages.append({"role": "user", "content": req.message})

    if req.message_media_values:
        logger.debug(f"Message Media Values: {req.message_media_values}")
        messages.append({"role": "user", "content": f"Description of User Provided Images:\n{req.message_media_values}"})

    # Define tools
    tools = [
        {
            "type": "function",
            "function": {
                "name": "search_database",
                "description": "Retrieve answer from the database based on a given query.",
                "strict": True,
                "parameters": {
                    "type": "object",
                    "properties": {
                        "query": {
                            "type": "string",
                            "description": "The search query to find relevant data in the database."
                        }
                    },
                    "required": ["query"],
                    "additionalProperties": False
                }
            }
        },
      
        {
            "type": "function",
            "function": {
                "name": "initial_address_information",
                "description": "Information to greet the user with in the beginning of a new conversation.",
                "parameters": {
                    "type": "object",
                    "properties": {},
                    "required": []
                }
            }
        },
        {
            "type": "function",
            "function": {
                "name": "handle_booking",
                "description": "Handle booking-related queries.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "customer_name": {
                            "type": "string",
                            # "format": "date",
                            "description": "The name of the customer to book the appointment under.",
                        },
                        "customer_phone_no": {
                            "type": "string",
                            "description": "The phone number of the customer to book the appointment for. It must be a valid phone number.",
                        },
                        "customer_age": {
                            "type": "string",
                            "description": "The age of the customer to book the appointment under.",
                        },
                        "customer_medical_history": {
                            "type": "string",
                            "description": "The medical history of the customer to book the appointment under.",
                        },
                        "description": {
                            "type": "string",
                            "description": "Detailed Description of the booking request.",
                        },
                    },
                    "required": ["customer_name", "customer_phone_no", "customer_age", "customer_medical_history", "description"],
                }
            }
        },
        
        {
            "type": "function",
            "function": {
                "name": "create_issue_tickets",
                "description": "Create a new issue ticket. If issue_type is not specified, it will default to 'ticket'.",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "name": {
                            "type": "string",
                            "description": "Short title for the issue"
                        },
                        "issue_type": {
                            "type": "string",
                            "enum": [i.value for i in CTAType],
                            "description": "Type of issue (optional, defaults to 'ticket' if not provided)"
                        },
                        "description": {
                            "type": "string",
                            "description": "Detailed description of the issue"
                        },
                    },
                    "required": ["name", "description"]
                }
            }
        },
    
    ]

    # Initial API call
    response = openai_client.chat.completions.create(
        model=SYS_PROMPT["model"],
        messages=messages,
        tools=tools,
        tool_choice="auto",
        parallel_tool_calls=True,
    )
    original_usage ={"model":SYS_PROMPT["model"], **response.usage.model_dump()}

 

    # Allow multiple rounds of tool calls
    max_tool_calls = 5  # Prevent infinite loops
    current_calls = 0
    token_ussage={}
    while current_calls < max_tool_calls:
        current_calls += 1
        assistant_message = response.choices[0].message
        messages.append(assistant_message)

        if not assistant_message.tool_calls:
            break

        tool_calls = assistant_message.tool_calls

        # Handle all tool calls in this round
        for tool_call in assistant_message.tool_calls:
            function_name = tool_call.function.name
            function_args = json.loads(tool_call.function.arguments)

            # Execute the appropriate function
            if function_name == "search_database":
                # print(f"Round {current_calls} - FUNCTION ARGS for search: {function_args}")

                result, extracted_metadata = await generate_answer_from_query(query=function_args["query"], qd_client=qd_client, current_user=current_user)
                extracted_metadata = extracted_metadata

           

            elif function_name == "initial_address_information":
                # print(f"Round {current_calls} - FUNCTION ARGS for initial: {function_args}")
                result = initial_address_information(db=current_user.db)
            elif function_name == "create_issue_tickets":
                print(f"Round {current_calls} - FUNCTION ARGS for create: {function_args}")
                
                if not function_args.get("issue_type"):
                    print("Issue type not provided, defaulting to ticket")
                    function_args["issue_type"] = CTAType.TICKET.value
                result = create_issue_tickets(function_args["name"], function_args["issue_type"], function_args["description"], req, current_user,req.channel)
                function_args["cta_id"] = result["cta_id"]

            elif function_name == "handle_booking":
                # print(f"Round {current_calls} - FUNCTION ARGS for handle: {function_args}")
                result,data = handle_booking(
                    function_args.get("customer_name"),
                    function_args.get("customer_phone_no"),
                    function_args.get("customer_age"),
                    function_args.get("customer_medical_history"),
                    function_args.get("description"),
                    req,
                    current_user,
                )
                function_args["cta_id"] = data["cta_id"]
                function_args["issue_type"] = CTAType.BOOKING.value

            else:
                result = {"error": f"Unknown function: {function_name}"}

            tool_calls_results.append({
                "result": result,
                "function_name": function_name,
                "function_args": function_args
            })
            messages.append({
                "role": "tool",
                "name": function_name,
                "content": json.dumps(result),
                "tool_call_id": tool_call.id
            })

        # Get next response with tool results
        response = openai_client.chat.completions.create(
            model=SYS_PROMPT["model"],
            messages=messages,
            tools=tools,
            tool_choice="auto",  # Allow more tool calls if needed
        )
        token_ussage={"model":"gpt-4o", **response.usage.model_dump()}
        # final_response = response.choices[0].message.content
        # messages.append(response.choices[0].message)
    # Final response without tools to summarize all findings
    messages.append({"role": "user", "content": req.message})
    messages.append({"role": "assistant", "content": response.choices[0].message.content})
    # final_call = openai_client.chat.completions.create(
    #     model="gpt-4o",
    #     messages=messages,
    #     tools=tools,
    #     tool_choice="none"  # Don't allow additional tool calls
    # )
    # final_response = final_call.choices[0].message.content
    from pprint import pprint
    pprint(messages)


    return messages[-1]["content"], {
        "source_nodes": source_nodes,
        "tool_calls": tool_calls,
        "tool_calls_results": tool_calls_results,
        "identified_product": identified_product,
        "language": language,
        "token_usage": {
            "input_tokens": original_usage,
            "output_tokens": token_ussage,
            "lang_usage": lang_usage,
            "identify_prod_usage": prod_usage
        },
        "image_process_cost": req.image_process_metadata
    }